checkPythonVersion() {
    if command -v python3 &>/dev/null
    then
        version_output=$(python3 --version 2>&1)
        # Expected output format: "Python X.Y.Z"
        version=$(echo "$version_output" | awk '{print $2}')
        major=$(echo "$version" | cut -d. -f1)
        minor=$(echo "$version" | cut -d. -f2)

        if [ "$major" -eq "3" ] && [ "$minor" -ge "8" ]
        then
            echo "Python version $version is installed and meets the requirement (>=3.8)."
            python3_bin="python3"
            return 0
        else
            echo "Installed Python version ($version) is less than 3.8."
            echo "Looking for additional python versions..."
            for ver in {8..13}
            do
                cmd="python3.$ver"
                if command -v "$cmd" &> /dev/null
                then
                    echo "Found: $cmd -> $("$cmd" --version)"
                    python3_bin=$cmd
                fi
            done
            if [[ "${python3_bin}x" != "x" ]]
            then
                echo "Using the python >>> $python3_bin <<<."
                return 0
            else
                echo "Did not find an alternative Python."
                return 1
            fi
        fi
    else
        echo "Python3 is not installed."
        return 2
    fi
}

checkLinuxDistro()
{
    echo "If you know what you are doing, please use --force option to avoid our Linux Distro compatibility test."

    if [ -f /etc/redhat-release ]
    then
        release_info=$(cat /etc/redhat-release)

        if echo $release_info | egrep -iq centos
        then
            redhat_distro_based="true"
        else
            if echo $release_info | egrep -iq almalinux
            then
                redhat_distro_based="true"
            else
                if echo $release_info | egrep -iq rocky
                then
                    redhat_distro_based="true"
                fi
            fi
        fi

        if [[ "${redhat_distro_based}" == "true" ]]
        then
            if echo "$release_info" | egrep -iq stream
            then
                redhat_distro_based_version=$(cat /etc/redhat-release  |  grep -oE '[0-9]+' | head -n 1)
            else
                redhat_distro_based_version=$(echo "$release_info" | grep -oE '[0-9]+\.[0-9]+' | cut -d. -f1)
            fi

            if [[ ! $redhat_distro_based_version =~ ^[789]$ ]]
            then
                echo "Your RedHat Based Linux distro version..."
                cat /etc/redhat-release
                echo "is not supported. Aborting..."
                exit 18
            fi
        else
            echo "Your RedHat Based Linux distro..."
            cat /etc/redhat-release
            echo "is not supported. Aborting..."
            exit 19
        fi
    else
        if [ -f /etc/debian_version ]
        then
            if cat /etc/issue | egrep -iq "ubuntu"
            then
                ubuntu_distro="true"
                ubuntu_version=$(lsb_release -rs)
                ubuntu_major_version=$(echo $ubuntu_version | cut -d '.' -f 1)
                ubuntu_minor_version=$(echo $ubuntu_version | cut -d '.' -f 2)
                if ( [[ $ubuntu_major_version -lt 18 ]] || [[ $ubuntu_major_version -gt 24  ]] ) && [[ $ubuntu_minor_version -ne 04 ]]
                then
                    echo "Your Ubuntu version >>> $ubuntu_version <<< is not supported. Aborting..."
                    exit 20
                fi
            else
                echo "Your Debian Based Linxu distro is not supported."
                echo "Aborting..."
                exit 21
            fi
        else
            echo "Not able to find which distro you are using."
            echo "Aborting..."
            exit 22
        fi
    fi
}

checkDcvConfPath()
{
    if [ ! -f $dcv_conf_path ]
    then
    	echo "The file >>> $dcv_conf_path <<< was not found. Aborting..."
    	exit 6
    fi
}

createDirectories()
{
    # create the directories
    sudo mkdir -p $dcv_management_dir
    sudo mkdir -p /var/run/dcvsimpleextauth
    sudo mkdir -p $dcv_tokens_path
    sudo mkdir -p /etc/dcv-management/sessions-permissions.d
    sudo mkdir -p /etc/dcv-management/notifications.d/
}

createSettingsFile()
{
     cat <<EOF | sudo tee $dcv_management_file_conf_path_scheme
session_type=virtual
session_auto_creation_by_dcv=false
session_timeout=3600
dcv_collab=false
dcv_collab_prompt_timeout=20
dcv_collab_session_name=
dcv_collab_sessions_permissions_dir=/etc/dcv-management/sessions-permissions.d
dcv_management_maintenance_dir=/etc/dcv-management/notifications.d/
dcv_management_maintenance_timeout=20
EOF
   
    # do not create the file again if already exist
    if [ ! -f $dcv_management_file_conf_path ]
    then
        sudo cp -a $dcv_management_file_conf_path_scheme $dcv_management_file_conf_path
    else
        timestamp=$(date +"%Y%m%d_%H%M%S")
        backup_file="${dcv_management_file_conf_path}.${timestamp}"
        sudo cp -a $dcv_management_file_conf_path $backup_file

        # Loop through each non-empty line in the default file
        while IFS= read -r line || [ -n "$line" ]
        do

            # Skip empty lines or lines without an '=' sign
            if [[ -z "$line" || "$line" != *"="* ]]
            then
                continue
            fi

            # Remove any comments at the beginning if needed (optional)
            # Uncomment the below to skip commented lines starting with '#' if applicable
            # [[ "$line" =~ ^[[:space:]]*# ]] && continue

            # Extract key: get part before the first '=' and trim surrounding spaces
            key=$(echo "$line" | sed 's/ *=.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')

            # Check if the key already exists in the user file (ignoring spaces around key)
            if ! grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$dcv_management_file_conf_path"
            then
                echo "Adding missing setting: $line"
                echo "$line" | sudo tee -a "$dcv_management_file_conf_path" >/dev/null
            fi
        done < "$dcv_management_file_conf_path_scheme"
        
    fi
}

copyPythonApp()
{
    # copy the python app
    sudo cp -f api/app.py $dcv_management_dir
}

setupRedhatPackages()
{
    sudo yum -y install ${python3_bin}-pip jq
}

setupUbuntuPackages()
{
    sudo apt update
    sudo apt -y install ${python3_bin}-pip jq
}

setupPythonRequiredLibraries()
{
    sudo "${python3_bin}" -m pip install --upgrade pip
    sudo "${python3_bin}" -m pip install Flask --ignore-installed -U blinker
    sudo "${python3_bin}" -m pip install --upgrade setuptools
    sudo "${python3_bin}" -m pip install paramiko
}

setAuthTokenVerifier()
{
    # Configure the auth-token-verifier
    if grep -q "auth-token-verifier" "$dcv_conf_path"
    then
        sudo sed -i "s/auth-token-verifier.*/$auth_token_line_to_add/" "$dcv_conf_path"
    else
        sudo sed -i "/^\[security\]/a $auth_token_line_to_add" "$dcv_conf_path"
    fi
}

setupScripts()
{
    # Install scripts
    for script_name in $dcv_notify_users $dcv_collab_prompt_script $dcv_local_sessions
    do
        script_file_name=$(basename ${script_name})
        sudo cp ${script_file_name}.sh $script_name
        sudo chmod +x $script_name
    done

    # Create the script that will create and return the token
    cat <<EOF | sudo tee /usr/bin/dcv_get_token
#!/bin/bash

dcv_tokens_path="$dcv_tokens_path"
token_expiration_time_in_seconds=\$1
token=\$(openssl rand -hex 8 | tr -d '\n')
token_timestamp=\$(date +%s)

if echo \$token_expiration_time_in_seconds | egrep -iq "^[0-9]+$"
then
        echo \$token | sudo dcvsimpleextauth add-user --session \$USER --auth-dir /var/run/dcvsimpleextauth/ --user \$USER --append

        cat <<END_DATA | sudo tee \${dcv_tokens_path}/\${USER}.\${token} | > /dev/null
\${USER};\${token};\${token_timestamp};\${token_expiration_time_in_seconds}
END_DATA

        echo \$token
else
        echo "Expire time is invalid. Please insert a integer value greater than 0, in seconds."
fi
EOF

    # create the script that will close expired tokens
    cat <<EOF | sudo tee /usr/bin/dcv_tokens_check
#!/bin/bash

tokens_files_list=\$(ls $dcv_tokens_path)
for token_file in \$tokens_files_list
do
        session_id=\$(cat \$token_file | cut -d";" -f1)
        session_token=\$(cat \$token_file | cut -d";" -f2)
        session_timestamp=\$(cat \$token_file | cut -d";" -f3)
        session_expiration_time=\$(cat \$token_file | cut -d";" -f4)
        current_time=\$(date +%s)
        time_diff=\$(( current_time - session_timestamp))
        if [[ \$time_diff -gt \$session_expiration_time ]]
        then
                sudo dcvsimpleextauth remove-auth --session \$session_id
                sudo rm -f \$token_file
        fi
done

EOF

    # Create the service that will check the created tokens
    cat <<EOF | sudo tee /etc/systemd/system/dcvtoken.service
[Unit]
Description=DCV Tokens checks service

[Service]
Type=oneshot
After=network.target
User=root
ExecStart=/bin/bash /usr/bin/dcv_tokens_check
EOF

    cat <<EOF | sudo tee /etc/systemd/system/dcvtoken.timer
[Unit]
Description=Timer to execute dcvtoken.service oneshot

[Timer]
OnCalendar=*:0/10

[Install]
WantedBy=timers.target
EOF

    # Create DCV Management systemd service
    cat <<EOF | sudo tee /etc/systemd/system/dcv-management.service
[Unit]
Description=DCV Management API Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/dcv_api
ExecStart=/usr/bin/${python3_bin} /opt/dcv_api/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # create the dcv_local_sessions_timedout script
    cat <<EOF | sudo tee /usr/bin/dcv_local_sessions_timedout
#!/bin/bash
session_list=\$(curl -s http://localhost:5000/list-sessions-json | jq -r '.message[] | .id' | paste -sd " " )
for session_id in \$session_list
do
	curl -s http://localhost:5000/check-session-timedout?session_id=\$session_id &> /dev/null
done
EOF

    # create the custom dcv pam file
    # backup it if already exist
    if [ -f "$dcv_pamd_file_conf" ]
    then
        timestamp=$(date +%s)
        backup_file="${dcv_pamd_file_conf}.backup.${timestamp}"
        sudo cp "$dcv_pamd_file_conf" "$backup_file"
    fi

    cat <<EOF | sudo tee $dcv_pamd_file_conf
auth    include dcv-password-auth
auth        required      pam_exec.so /usr/bin/dcv_local_sessions
account include dcv-password-auth 
EOF
    
    cat <<EOF | sudo tee /etc/pam.d/dcv-password-auth
# here are the per-package modules (the "Primary" block)
auth    [success=2 default=ignore]      pam_unix.so nullok
auth    [success=1 default=ignore]      pam_sss.so use_first_pass
# here's the fallback if no module succeeds
auth    requisite                       pam_deny.so
# prime the stack with a positive return value if there isn't one already;
# this avoids us returning an error just because nothing sets a success code
# since the modules above will each just jump around
auth    required                        pam_permit.so
# and here are more per-package modules (the "Additional" block)
auth    optional                        pam_cap.so
# end of pam-auth-update config

# here are the per-package modules (the "Primary" block)
account [success=1 new_authtok_reqd=done default=ignore]        pam_unix.so
# here's the fallback if no module succeeds
account requisite                       pam_deny.so
# prime the stack with a positive return value if there isn't one already;
# this avoids us returning an error just because nothing sets a success code
# since the modules above will each just jump around
account required                        pam_permit.so
# and here are more per-package modules (the "Additional" block)
account sufficient                      pam_localuser.so
account [default=bad success=ok user_unknown=ignore]    pam_sss.so
# end of pam-auth-update config
EOF

    # set execution permission
    sudo chmod +x /usr/bin/dcv_local_sessions
    sudo chmod +x /usr/bin/dcv_local_sessions_timedout

    if [ ! -f /var/spool/cron/root ]
    then
    	sudo touch /var/spool/cron/root
    	sudo chmod 600 /var/spool/cron/root
    fi

    # setup the cron to execute dcv_local_sessions_timedout
    if ! cat /var/spool/cron/root | egrep -iq "dcv_local_sessions_timedout"
    then
        cat <<EOF | sudo tee --append /var/spool/cron/root
0,30 * * * * /usr/bin/dcv_local_sessions_timedout &> /dev/null
EOF
    fi
}

enableSystemdServices()
{
    # enable the services
    sudo systemctl daemon-reload
    sudo systemctl enable --now dcv-management.service
    sudo systemctl enable --now dcvtoken.timer
}

restartSystemdServices()
{
    # restart the services in case of you are updating your setup
    sudo systemctl restart dcv-management.service
}

setDcvServerCustomPam()
{
    # configure the dcv server to use the custom pam file
    line_to_add="pam-service-name=\"$dcv_pamd_file_name\""
    if grep -q "^pam-service-name" "$dcv_conf_path"
    then
        sudo sed -i "s/pam-service-name.*/$line_to_add/" "$dcv_conf_path"
    else
        sudo sed -i "/^\[security\]/a $line_to_add" "$dcv_conf_path"
    fi

    # restart the dcv server to read the new pam service
    sudo systemctl restart dcvserver
}
