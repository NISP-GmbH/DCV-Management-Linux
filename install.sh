#!/bin/bash

# variables to setup the services
source config.conf
source library.sh

# check parameters
while [[ "$#" -gt 0 ]]
do
    case "$1" in
        --force)
            setup_force=true
            ;;
        *)
            echo "Unknown parameter $1"
            exit 1
            ;;
    esac
    shift
done

main()
{
    if [[ "$setup_force" == "false" ]]
    then
        checkLinuxDistro
    else
        echo "Which distro you are using? Type >>> ubuntu <<< for Ubuntu based or >>> redhat <<< for RedHat based"
        read linux_distro
        if echo $linux_distro | egrep -iq "ubuntu"
        then
            ubuntu_distro="true"
        else
            if echo $linux_distro | egrep -iq "redhat"
            then
                redhat_distro_based="true"
            else
                echo "Not recognized Linux distro. Aborting..."
                exit 8
            fi
        fi
    fi
    checkDcvConfPath

    if [[ "${ubuntu_distro}" == "false" ]]
    then
        if [[ "${redhat_distro_based}" == "false" ]]
        then
            echo "Is not possible to setup any package. Aborting..."
            exit 7
        else
            setupRedhatPackages
        fi
    else
        setupUbuntuPackages
    fi

    # if the setup already exist, then we need to reboot systemd services in the end
    if [ -f $dcv_management_file_conf_path ]
    then
        need_to_restart=1
    else
        need_to_restart=0
    fi

    createDirectories
    createSettingsFile
    copyPythonApp
    setupPythonRequiredLibraries
    setAuthTokenVerifier
    setupScripts
    enableSystemdServices
    setDcvServerCustomPam

    if  [ $need_to_restart -eq 1 ]
    then
        restartSystemdServices
    fi

    exit 0
}

main

# unknown error
exit 255
