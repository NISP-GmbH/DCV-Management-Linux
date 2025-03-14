# Dynamic DCV Sessions and permissions

The standard approach for NICE DCV sessions is to have a session statically created for a specific user during the DCV Server start.

There are some specific cases that you need dynamically create and close sessions or change the session permissions based in some rules.

There are some ways to create and manage sessions permissions.
1. Create static session (DCV default config) and configure the default.perm file to allow one or more users/groups to access the session (DCV session takeover).
2. Create and close manually the sessions, and then set the permissions, using command line.
3. Use DCV Management Linux to manage the session: Auto session creation during user login, for Virtual sessions, or automatically permission changes (aka Collaboration session) for Console sessions.

## DCV Dynamic sessions by DCV configuration

The guide to implement this approach is here: https://www.ni-sp.com/nice-dcv-dynamic-console-sessions/

## DCV Management Linux

This solution implement a Python service that can manage the DCV Server resources to make possible some customizations.

The DCV Management service is currently capable to do:
* Request token access to access your session using SSH service
* Count sessions by owner
* Create a session
* Create a session during new PAM login
* Close a session
* List connections
* List sessions
* List sessions by owner
* Check session timedout
* Collaboration session: The session owner will control the session and additional users can ask to see (without control) the owner session
* Schedule notifications to send to GNOME session users, get the answer and store in the systemd journal

Advantages of the local Python HTTP API:
* Do not need to use SUDO anymore, as we can control the service using http calls
* Do not provide admin privileges (root) to the user anymore, as the API has all the privileges needed
* Easier to read and parse JSON input. ref: https://docs.python.org/3/library/json.html
* Read, parse and write in config files that use sections (like dcv.conf), using Python configparser, in a way much easier than using bash. ref:  https://docs.python.org/3/library/configparser.html
* Python3.x is available since 2009, and 3.6 since 2016. So all distros, mainly the server editions, has Python3 to run the API
* Python Flask was used to write the API; Simple library (does not depend of other libraries), where we can write a very simple code, spending more time in the company solutions than in library syntax. ref: https://flask.palletsprojects.com/en/3.0.x/quickstart/
* The Python code is organized due the mandatory indentation. Also is simple, so anyone can read and understand, besides the syntax. Also, AI's like ChatGPT, Gemini etc are very efficient to understand Python code. Also Python is a base language for many distros, like Bash and Perl.

### Notification system

![Image](https://github.com/user-attachments/assets/db8357d0-d798-46e3-be85-2c0656244515)

If you want to notify all users by something, you can schedule an event and then run a cronjob to process this event from time-to-time. All GNOME sessions active during the cronjob execution will receive a notification. The answer (or timeout to answer) will be logged in the systemd journal. The user will also receive the notification 20 seconds after the authentication.

* To schedule an event:
```bash
curl -X POST "http://localhost:5000/schedule-notification" \
  -H "Content-Type: application/json" \
  -d '{
    "year": 2025,
    "month": 3,
    "day": 14,
    "hour": 15,
    "minute": 30,
    "title": "Maintenance scheduled",
    "text": "In the day 14, month 3, ywaer 2025, at 15:30, this server will reboot for maintenance.",
    "type": "maintenance",
    "button1": "Aware, agree",
    "button2": "Aware, not agree"
    "button2": "Help!"
  }'
``` 

__Notes:__
* You can create multiple buttons (1, 2, 3, ... , n)
* If the user does not answer or just exit the window, everything will be logged
* You can check the event answers executing:
```bash
journalctl --no-page | grep "\[DCV Management Notification\]"
```

Every notification will create a file that will be stored in:
```bash
/etc/dcv-management/notifications.d/
```

You can manually edit the notifications files, but we recommend create a new event using curl and remove the file that you want to change to avoid syntax issues.

When the event is in the past, the users will not be notified anymore.

To process the events from time-to-time, you can crate a cronjob that will do:
```bash
curl "http://localhost:5000/process-notifications"
```

If you want to process just specific event in a specific cronjob, you can also send the notification type. The other types will be ignored.
```bash
curl -s http://localhost:5000/process-notifications?type=maintenance
```

### Collaboration session

![Image](https://github.com/user-attachments/assets/529dfca0-36f5-4d92-82d4-5059c39667c4)

To enable the feature, you need to edit /etc/dcv-management/settings.conf and enable:

```bash
session_type=virtual
dcv_collab=true
```

* session_type : virtual or console
* dcv_collab : true or false

Additional and optional parameters:
```bash
dcv_collab_prompt_timeout=20 
dcv_collab_session_name=
dcv_collab_sessions_permissions_dir=/etc/dcv-management/sessions-permissions.d
```

Explaining:
* dcv_collab : (true|false) Will enable or disable the collaboration feature
* session_type : (console|virtual) the type of the session that will use collab feature.
* dcv_collab_prompt_timeout : the timeout (in seconds) to wait session owner approval before automatically deny the user access
* dcv_collab_session_name : you can set the name of the session that will use collab feature. If you do not set, it will use the first session according "dcv list-sessions" command.
* dcv_collab_sessions_permissions_dir : where will be stored the approved users for that session. You can safely remove any files, the API service will create again when needed.

How collaboration session works:
If the type is console session, the first to connect into the session will be the session owner with all session features. If an additional user try to login, the session owner will be requested to approve or deny. If approved, the user will have just the display (screen share) feature enabled.

### Supported Operating Systems

- RedHat based Linux distros (7, 8 and 9): CentOS, CentOS Stream, RockyLinux and AlmaLinux
- Ubuntu 18.04, 20.04, 22.04 and 24.04


### Installing DCV Managament Linux
```
bash install.sh
```

If you intend to install in a server that has no connection with internet here are some tips:
* Download the python packages to setup in the same server (please use the same python major version to execute pip3 commands).
```bash
# to download the python packages
pip3 download -r python_requirements.txt -d ./offline_packages
# to install the python packages
pip3 install ./offline_packages/*.whl
```
* If the server has a python lower than 3.8, you need to mount a local media or repository that will offer python3.8+ version to be installed.

### Updating DCV Managament Linux
```
bash install.sh
```

**Note:** settings.conf will be preserver and eventually merged if there are new parameters. Before that a backup will be created inside of /etc/dcv-management/.

### Uninstall DCV Management Linux
```
bash uninstall.sh
```

### HTTP requests to the DCV Management API Service

#### Sessions

* Create a session
```bash
curl "http://localhost:5000/create-session?owner=john"
```

* Close the session
```bash
curl "http://localhost:5000/close-session?session_id=session123"
```

* List session id connections
```bash
curl "http://localhost:5000/list-connections?session_id=john"
```

* Get the session owner given a session name
```bash
curl "http://localhost:5000/get-session-owner?session_name=mySession"
```

* Count sessions by owner
```bash
curl "http://localhost:5000/count-sessions-by-owner?owner=john"
```

* List all session owners
```bash
curl "http://localhost:5000/list-sessions-owners"
```

* List sessions by with cli result or json
```bash
curl "http://localhost:5000/list-sessions"
curl "http://localhost:5000/list-sessions-json"
```

#### Session Timeout

* Check for session timeout
```bash
curl "http://localhost:5000/check-session-timedout?session_id=session123"
```

#### Collaboration

* Remove one user from collaboration session
```bash
curl -X POST "http://localhost:5000/remove-permission?collab_owner_username=john&collab_session_name=session123&collab_del_username=alice"
```

* Ask to collaboration session owner to approve a new user to see the screen
```bash
curl -X POST "http://localhost:5000/approve-login?collab_session_owner=john&session_id=session123&collab_username=alice"
```

* Set the collaboration session owner
```bash
curl -X POST "http://localhost:5000/collab-set-session-owner?session_id=session123&session_owner=john"
```

* Check collaboration settings
```bash
curl "http://localhost:5000/check-collab-settings"
```

#### Notifications
* Process all possible notifications to specific user by dcv_local_sessions script:
```bash
curl "http://localhost:5000/process-notification-auth?username=alice"
```

* Process all possible notifications to all logged users or specific user:
```bash
curl "http://localhost:5000/process-notifications"
curl "http://localhost:5000/process-notifications?username=alice"
```

* Schedule a notification to send to all users:
```bash
curl -X POST "http://localhost:5000/schedule-notification" \
  -H "Content-Type: application/json" \
  -d '{
    "year": 2025,
    "month": 3,
    "day": 14,
    "hour": 15,
    "minute": 30,
    "title": "Test Notification",
    "text": "This is a test notification.",
    "type": "Maintenance",
    "button1": "Aware",
    "button2": "Help"
    "button2": "Exit"
  }'
```

## DCV Dynamic Session Creation

When the user login in DCV web dashboard, it will use Linux PAM service to do the authentication. The PAM config file is
```
/etc/pam.d/dcv.custom
```

and was configured in
```
/etc/dcv/dcv.conf
```

Before the authentication process finishes, it will execute this script:
```
/usr/bin/dcv_local_sessions
```

This script will check if the session exist and, if not, it will create a session dinamically. As the script will request the API service to create the session; No admin permissions are needed.

## Configuration file (/etc/dcv-management/settings.conf)

You can edit the settings.conf file to customize the dcv-management service. Currently here are the supported configs:
- session_type=virtual or session_type=console ; You can exchange the type of the session that will be created. You do not need to restart the service when you change this setting. If you set a different value, the virtual configuration will be the fallback.


## To update

If you already installed DCV Management and you need to update from the git, just do "git pull" or clone the repository again and execute the installation file. It will automatically update your setup.

# Logs
All requests to DCV Management API Service will be logged under journal log. You can check the logs using the commands below.

Complete log:
```
journalctl -u dcv-management.service
```

Live log:
```
journalctl -u dcv-management.service -f
```

# DCV SSH Key Authentication

Allow sessions being authenticated by ssh private/public key.

## How ssh private/public key works
The ssh client connects to the ssh server and requests a challenge. This challenge will be encrypted using the public key installed in the server. Then the ssh server will return this encrypted challenge to the ssh client, and if the ssh client has the right private key, it will decrypt the challenge and return to the ssh server. If the ssh server receives the right decrypted challenge, it will approve the ssh session.

### The first approach for DCV SSH Key Authentication: The user executes a bash script or ssh command
As the ssh client already is capable to do ssh authentication challenge, we can create the token during PAM auth and return it to the customer. Then the user can run the command dcv_get_token.


We provided a script to do that, but you can also use do a ssh command:

Copy the tools/get_token_authenticated_by_ssh.sh to your enviroment, configure the variables inside of the script and then, to get the token, execute the script:
```bash
bash get_token_authenticated_by_ssh.sh time_to_expire_in_seconds
```

The time_to_expire_in_seconds needs to be an integer greater than 0 in seconds. For example:

```bash
bash get_token_authenticated_by_ssh.sh 3600
```

This will create a token that will be available for one hour.

You can also execute a ssh command if you do not want to use the script:

```bash
ssh -i $ssh_private_key -u ssh_user -h ssh_host -p 22 "/usr/bin/dcv_get_token time_to_expire_in_seconds"
```

### Upcoming: The second approach: Using HTTP requests
This approach intends to be a solution for any app that wants to create DCV sessions authenticated by ssh. As there is a challenge (i.e. interaction) between an API server or SSH server, this script needs to be executed in a language like Python, PHP etc. This approach targets to be a generic solution for any kind of software (that usually are capable to do HTTP requests).
