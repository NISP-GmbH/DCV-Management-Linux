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
collab_enabled=$(echo "$curl_result" | grep '"collab_enabled"' | sed 's/.*"collab_enabled":[[:space:]]*\([^,}]*\).*/\1/')

# if enabled, get the collab session name
if echo $collab_enabled | egrep -iq "true"
then
    collab_session_name=$(echo "$curl_result" | grep '"session_name"' | sed 's/.*"session_name":[[:space:]]*"\([^"]*\)".*/\1/')
    curl_result=$(curl -s http://${hostname}:${port}/get-session-owner?session_name=${collab_session_name})
    collab_session_owner=$(echo "$curl_result" | sed -n 's/.*"owner"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
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
            curl_result=$(curl -s -X POST "http://${hostname}:${port}/approve-login?username=${collab_session_owner}&collab_username=${username}")
            approval=$(echo "$curl_result" | grep -o '"message": *[^,}]*' | sed 's/"message": *\(.*\)/\1/')
            approval=$(echo "$approval" | tr -d ' "')

            if echo $approval | egrep -iq "true"
            then
                exit 0
            else
                exit 3
            fi
        fi
    # and the collab session is closed
    else
        curl -s http://${hostname}:${port}/create-session?owner=$username 2>&1 >> /dev/null
        if [ $? -eq 0 ]
        then
            exit 0
        else
            exit 1
        fi
    fi
fi
