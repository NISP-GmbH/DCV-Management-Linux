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
    createDirectories
    copyPythonApp
    setupRequiredLibraries
    setAuthTokenVerifier
    setupScripts
    enableSystemdServices
    setDcvServerCustomPam
    exit 0
}

# unknown error
exit 255
