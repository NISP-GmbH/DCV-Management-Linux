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
                redhat_distro_based_version=$(cat /etc/redhat-release  |  grep -oE '[0-9]+')
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
}

createSettingsFile()
{
    # do not create the file again if already exist
    if [ ! -f $dcv_management_file_conf_path ]
    then
    cat <<EOF | sudo tee $dcv_management_file_conf_path
session_type=virtual
session_auto_creation_by_dcv=false
dcv_collab=false
dcv_collab_prompt_timeout=20
dcv_collab_session_name=
dcv_collab_sessions_permissions_dir=/etc/dcv-management/sessions-permissions.d
EOF
    fi
}

copyPythonApp()
{
    # copy the python app
    sudo cp -f api/app.py $dcv_management_dir
}

setupRedhatPackages()
{
    sudo yum -y install python38 python38-pip jq
    sudo pip3.8 install --upgrade pip
}

setupUbuntuPackages()
{
    sudo apt update
    sudo apt -y install python3.8 python3-pip jq
    sudo pip3 install --upgrade pip 
}

setupPythonRequiredLibraries()
{
    if command -v pip3.8 &> /dev/null
    then
        sudo pip3.8 install --upgrade pip
        sudo pip3.8 install Flask --ignore-installed -U blinker
        sudo pip3.8 install --upgrade setuptools
        sudo pip3.8 install paramiko

    else
        sudo pip3 install --upgrade pip
        sudo pip3 install Flask --ignore-installed -U blinker
        sudo pip3 install --upgrade setuptools
        sudo pip3 install paramiko
    fi
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
    sudo cp $(basename $dcv_collab_prompt_script).sh $dcv_collab_prompt_script
    sudo chmod +x $dcv_collab_prompt_script
    sudo cp $(basename $dcv_local_sessions).sh $dcv_local_sessions
    sudo chmod +x $dcv_local_sessions

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
ExecStart=/usr/bin/python3.8 /opt/dcv_api/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # create the dcv_local_sessions_timedout script
    cat <<EOF | sudo tee /usr/bin/dcv_local_sessions_timedout
#!/bin/bash
session_owner_list=\$(curl -s http://localhost:5000/list-sessions-owners | grep -Eo '"([^"]+)"' | cut -d '"' -f2 | grep -iv message)
for owner in \$session_owner_list
do
	curl -s http://localhost:5000/check-session-timedout?owner=\$owner &> /dev/null
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
