# Dynamic DCV Sessions

The standard approach for NICE DCV Console sessions is to have a session statically created for a specific user. In some cases it is preferred to enable users to connect to NICE DCV and dynamically be able to use the DCV Console Session without installing and configuring the [DCV Session Manager](https://docs.aws.amazon.com/dcv/latest/sm-admin/what-is-sm.html).

Below we show 2 approaches for managing console sessions - based on permissions and a more controlled via a Python API server

# Always on Console session, permissions for all and only one connection allowed

To implement this we automatically create a console sessions for a specific standard user and set the maximal number of connection to the DCV console session to 1 so no other user can connect and allow all users to connect to the session in the permissions file. The guide to implement this approach is here: https://www.ni-sp.com/nice-dcv-dynamic-console-sessions/

In addition we can use commands to logout the user actively after timeout - we need to be aware that there could be open files without unsaved work in the session:
* sudo loginctl terminate-user $USER
* gnome-session-quit --no-prompt

# DCV Management Python API Server to manage DCV virtual and console sessions

The DCV Management service is currently capable to do:
* Request token access to access your session using SSH service
* Count sessions by owner
* Create a session
* Close a session
* List connections
* List sessions
* List sessions by owner
* Check session timedout

Advantages of the local Python HTTP API:
* Do not need to use SUDO anymore, as we can control the service using http calls
* Do not provide admin privileges (root) to the user anymore, as the API has all the privileges needed
* Easier to read and parse JSON input. ref: https://docs.python.org/3/library/json.html
* Read, parse and write in config files that use sections (like dcv.conf), using Python configparser, in a way much easier than using bash. ref:  https://docs.python.org/3/library/configparser.html
* Python3.x is available since 2009, and 3.6 since 2016. So all distros, mainly the server editions, has Python3 to run the API
* Python Flask was used to write the API; Simple library (does not depend of other libraries), where we can write a very simple code, spending more time in the company solutions than in library syntax. ref: https://flask.palletsprojects.com/en/3.0.x/quickstart/
* The Python code is organized due the mandatory indentation. Also is simple, so anyone can read and understand, besides the syntax. Also, AI's like ChatGPT, Gemini etc are very efficient to understand Python code. Also Python is a base language for many distros, like Bash and Perl.

## Installing DCV Managament API Service
```
bash install.sh
```

## Uninstall DCV Management API Service
```
bash uninstall.sh
```

## HTTP requests to the DCV Management API Service

* Counting how much sessions a specific owner has:
```
curl -s http://localhost:5000/count-sessions-by-owner?owner=francisco
```

* List all sessions
```
curl -s http://localhost:5000/list-sessions
```

* Create a session with specific owner:
```
curl -s http://localhost:5000/create-session?owner=centos
```
* Check a session with specific owner and close the session if there are no one connected in last 30 minutes
```
 curl -s http://localhost:5000/check-session-timedout?owner=francisco
```

* List all owners with sessions created
```
curl -s http://localhost:5000/list-sessions-owners
```

## DCV dynamic session creation

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

## DCV SSH Key Authentication

Allow sessions being authenticated by ssh private/public key.

### How ssh private/public key works
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
