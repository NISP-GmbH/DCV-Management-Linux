#!/bin/bash

source config.conf

# stop the systemd services
sudo systemctl stop dcv-management.service
sudo systemctl disable dcv-management.service

# remove the services directories
sudo rm -rf $dcv_management_dir
sudo rm -rf $dcv_tokens_path

# remove scripts
sudo rm -f /usr/bin/dcv_get_token
sudo rm -f /usr/bin/dcv_tokens_check
sudo rm -f /usr/bin/dcv_local_sessions_timedout
sudo rm -f /usr/bin/dcv_notify_users
sudo rm -f $dcv_notify_users
sudo rm -f $dcv_local_sessions
sudo rm -f $dcv_management_conf_path
sudo rm -f $dcv_pamd_file_conf
sudo sed '/^pam-service-name=.*$/d' /etc/dcv/dcv.conf
sudo sed '/^auth-token-verifier=.*$/d' /etc/dcv/dcv.conf

# remove the systemd services files
sudo rm -f /etc/systemd/system/dcvtoken.service
sudo rm -f /etc/systemd/system/dcvtoken.timer
sudo rm -f /etc/systemd/system/dcv-management.service

# reload the systemd daemon
sudo systemctl daemon-reload

# restart dcv server
sudo systemctl restart dcvserver

echo "The DCV Management Service was removed!"
