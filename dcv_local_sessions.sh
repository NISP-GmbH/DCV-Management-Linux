#!/bin/bash
#set -e

# variables
username=$PAM_USER
hostname="localhost"
port="5000"
debug="false"
debug_file_name="/tmp/dcv-management-auth-debug.log.$$"

# enable verbose if debug is true
if echo $debug | egrep -iq "true"
then
    exec 2>"${debug_file_name}";set -x
fi

# check if collab feature is enabled
curl_result=$(curl -s http://${hostname}:${port}/check-collab-settings 2> /dev/null)

if [[ "${curl_result}x" == x ]]
then
    exit 12
fi

collab_enabled=$(echo "$curl_result" | jq -r '.message.collab_enabled')
session_type=$(echo "$curl_result" | jq -r '.message.session_type')
session_auto_creation_by_dcv=$(echo $curl_result | jq -r '.message.session_auto_creation_by_dcv')

if ! echo $collab_enabled | egrep -iq "(true|false)"
then
    exit 13
fi

if ! echo $session_type | egrep -iq "(true|false)"
then
    exit 17
fi

if ! echo $session_auto_creation_by_dcv | egrep -iq "(true|false)"
then
    exit 16
fi

# if enabled, and the dcv server auto creation is enabled
if echo $collab_enabled | egrep -iq "true"
then
    if echo $session_auto_creation_by_dcv | egrep -iq "true"
    then
        # get the id of the session created by DCV
        curl_result=$(curl -s http://${hostname}:${port}/list-sessions-json)
        session_id=$(echo "$curl_result" | jq -r '.message[0].id')

        # Verify that an id was indeed extracted
        if [ -z "$session_id" ] || [ "$session_id" = "null" ]
        then
            echo "Error: session id not found in JSON output." >&2
            exit 14
        fi

        number_of_connections=$(echo "$curl_result" | jq -r '.message[0]["num-of-connections"]')
        if [ -z "$number_of_connections" ] || [ "$number_of_connections" = "null" ]
        then
            echo "Error: number_of_connections not found in JSON output." >&2
            exit 15
        fi        

        # if is the first user connected, it will be the owner
        if [ "$number_of_connections" -eq 0 ]
        then
            curl_result=$(curl -s -X POST "http://${hostname}:${port}/collab-set-session-owner?session_owner=${username}&session_id=${session_id}")
            exit 0
        else
            curl_result=$(curl -s -X GET "http://${hostname}:${port}/collab-get-session-owner")
            collab_session_owner=$(echo $curl_result | jq -r '.message.collab_session_owner')

            # if is not the first user connected, but is the owner
            if [[ "$username" == "$collab_session_owner" ]]
            then
                exit 0
            # if is not the first user connected, and is not the owner
            else
                curl_result=$(curl -s -X POST "http://${hostname}:${port}/approve-login?collab_session_owner=${collab_session_owner}&collab_username=${username}&number_of_connections=$number_of_connections&session_id=${session_id}")
                approval=$(echo "$curl_result" | jq -r ".message")

                if echo $approval | egrep -iq "true"
                then
                    exit 0
                else
                    exit 18
                fi
            fi
        fi
    fi
fi


# if enabled, get the collab session name
if echo $collab_enabled | egrep -iq "true"
then
    collab_session_name=$(echo "$curl_result" | jq -r '.message.session_name')
    if ! echo ${collab_session_name} | egrep -iq "null"
    then
        curl_result=$(curl -s http://${hostname}:${port}/get-session-owner?session_name=${collab_session_name})
        collab_session_owner=$(echo "$curl_result" | jq -r '.message.owner')
    else
        curl_result=$(curl -s http://${hostname}:${port}/get-first-session)
        collab_session_name=$(echo "$curl_result" | jq -r '.message')
        if ! echo $collab_session_name | egrep -iq "null"
        then
            curl_result=$(curl -s http://${hostname}:${port}/get-session-owner?session_name=${collab_session_name})
            collab_session_owner=$(echo "$curl_result" | jq -r '.message.owner')
        else
            collab_session_owner="thereisnocollabsessionavailable"
        fi
    fi
fi

# check if there is a session created
if curl -s http://${hostname}:${port}/list-sessions 2> /dev/null | egrep -iq "Session: [']${username}[']"
then
    session_created="true"
else
    session_created="false"
fi

# if collab is false
if echo $collab_enabled | egrep -iq "false"
then
    # if there is no session
    if echo $session_created | egrep -iq "false"
    then
        # create the session
        curl -s http://${hostname}:${port}/create-session?owner=$username 2>&1 >> /dev/null
        if [ $? -eq 0 ]
        then
            exit 0
        else
            exit 1
        fi
    # if there is a session
    else
        exit 0
    fi
fi

# if collab feature is enabled
if echo $collab_enabled | egrep -iq "true"
then
    # and the collab session is opened
    if curl -s http://${hostname}:${port}/list-sessions 2> /dev/null | egrep -iq "Session: [']${collab_session_name}[']"
    then
        # and if the user is the collab session owner
        if echo $username | egrep -iq "^${collab_session_owner}$"
        then
            exit 0
        # and the user is not the collab session owner
        else
            curl_result=$(curl -s -X POST "http://${hostname}:${port}/approve-login?collab_session_owner=${collab_session_owner}&collab_username=${username}")
            approval=$(echo "$curl_result" | jq -r ".message")

            if echo $approval | egrep -iq "true"
            then
                exit 0
            else
                exit 3
            fi
        fi
    # and if the collab session is closed
    else
        curl -s http://${hostname}:${port}/create-session?owner=$username 2>&1 >> /dev/null
        if [ $? -eq 0 ]
        then
            exit 0
        else
            exit 2
        fi
    fi
fi

# unknown error, do not authorize
exit 255
