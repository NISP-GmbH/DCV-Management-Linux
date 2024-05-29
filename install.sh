#!/bin/bashi

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
    fi
    checkDcvConfPath

    if [[ "{$ubuntu_version}x" == "x" ]]
    then
        if [[ "{$centos_version}x" == "x" ]]
        then
            echo "Is not possible to setup any package. Aborting..."
            exit 7
        else
            setupCentosPackages
        fi
    else
        setupUbuntuPackages
    fi

    createDirectories
    copyPythonApp
    setupPythonRequiredLibraries
    setAuthTokenVerifier
    setupScripts
    enableSystemdServices
    setDcvServerCustomPam
    exit 0
}

main

# unknown error
exit 255
