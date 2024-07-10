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
    sudo mkdir -p /etc/dcv-management/
}

createSettingsFile()
{
    # do not create the file again if already exist
    if [ ! -f $dcv_management_file_conf_path ]
    then
    cat <<EOF | sudo tee $dcv_management_file_conf_path
session_type=virtual
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
    sudo yum -y install python3-pip
    sudo pip3 install --upgrade pip
}

setupUbuntuPackages()
{
    sudo apt update
    sudo apt -y install python3-pip
    sudo pip3 install --upgrade pip 
}

setupPythonRequiredLibraries()
{
    # install required libraries
    sudo pip3 install --upgrade pip
    sudo pip3 install Flask --ignore-installed -U blinker
    sudo pip3 install --upgrade setuptools
    sudo pip3 install paramiko
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
ExecStart=/usr/bin/python3 /opt/dcv_api/app.py
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

    # create the script that will be executed by PAM during authentication
    cat <<EOF | sudo tee /usr/bin/dcv_local_sessions
#!/bin/bash
username=\$PAM_USER

if ! curl -s http://localhost:5000/list-sessions 2> /dev/null | grep -iq \$username
then
        curl -s http://localhost:5000/create-session?owner=\$username 2>&1 >> /dev/null
fi

if [ $? -eq 0 ]
then
	exit 0
else
	exit 1
fi
EOF

    # create the custom dcv pam file
    cat <<EOF | sudo tee $dcv_pamd_file_conf
auth        required      pam_exec.so /usr/bin/dcv_local_sessions
auth    include dcv-password-auth
account include dcv-password-auth 
EOF
    cat <<EOF | sudo tee /etc/pam.d/dcv-password-auth
auth        required                                     pam_env.so
auth        required                                     pam_faildelay.so delay=2000000
auth        [default=1 ignore=ignore success=ok]         pam_localuser.so
auth        sufficient                                   pam_unix.so nullok
auth        sufficient                                   pam_sss.so forward_pass
auth        required                                     pam_deny.so

account     required                                     pam_unix.so
account     sufficient                                   pam_localuser.so
account     [default=bad success=ok user_unknown=ignore] pam_sss.so
account     required                                     pam_permit.so

password    requisite                                    pam_pwquality.so local_users_only
password    sufficient                                   pam_unix.so sha512 shadow nullok use_authtok
password    [success=1 default=ignore]                   pam_localuser.so
password    sufficient                                   pam_sss.so use_authtok
password    required                                     pam_deny.so

session     optional                                     pam_keyinit.so revoke
session     required                                     pam_limits.so
-session    optional                                     pam_systemd.so
session     optional                                     pam_oddjob_mkhomedir.so
session     [success=1 default=ignore]                   pam_succeed_if.so service in crond quiet use_uid
session     required                                     pam_unix.so
session     optional                                     pam_sss.so
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
