import paramiko
from io import StringIO
from flask import Flask, request, jsonify
import subprocess
import os
import json
import re
import pwd
import stat
from datetime import datetime

app = Flask(__name__)

# Global variable
collab_session_owner = ""

def read_settings_conf():
    # Define fallback/default values
    settings = {
        "session_type": "virtual",
        "dcv_collab": "false",
        "session_auto_creation_by_dcv": "false",
        "session_timeout": 3600,
        "dcv_collab_prompt_timeout": 20,
        "dcv_collab_session_name": "",
        "dcv_collab_sessions_permissions_dir": "/etc/dcv-management/sessions-permissions.d"
    }
    try:
        with open('/etc/dcv-management/settings.conf', 'r') as file:
            for line in file:
                line = line.strip()
                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue
                if '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()
                    
                    # Remove surrounding single or double quotes from the value if present
                    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
                        value = value[1:-1].strip()
                    
                    # Update settings only if the key is one of the expected keys
                    if key in settings:
                        settings[key] = value
    except FileNotFoundError:
        print("settings.conf not found. Using default fallback values.")
    except Exception as e:
        print(f"Error reading settings.conf: {e}. Using default fallback values.")
    return settings
def manage_permission_file(collab_session_owner, collab_session_name, new_permission_line=None, overwrite=False):
    settings = read_settings_conf()
    session_perm_dir = settings.get('dcv_collab_sessions_permissions_dir', '')
    if not session_perm_dir:
        return {"message": "Session permissions directory is not configured."}, 500

    perm_file_path = os.path.join(session_perm_dir, f"{collab_session_name}.perm")
    created = False

    # Create or overwrite file with a base template
    if overwrite or not os.path.exists(perm_file_path):
        content = (
            "[groups]\n\n"
            "[aliases]\n\n"
            "[permissions]\n"
            f"{collab_session_owner} allow builtin\n"
        )
        with open(perm_file_path, 'w') as f:
            f.write(content)
        created = True
    elif new_permission_line:
        # File exists so update it: add new_permission_line to the [permissions] section if missing
        with open(perm_file_path, 'r') as f:
            lines = f.readlines()

        updated = False
        new_lines = []
        in_permissions = False
        for i, line in enumerate(lines):
            new_lines.append(line)
            if line.strip() == "[permissions]":
                in_permissions = True
                # Check whether the new_permission_line is already present until another section starts
                found = False
                for subsequent_line in lines[i+1:]:
                    if subsequent_line.strip().startswith('['):  # reached next section
                        break
                    if subsequent_line.strip() == new_permission_line:
                        found = True
                        break
                if not found:
                    new_lines.append(new_permission_line + "\n")
                    updated = True
        # If there was no [permissions] section, add one at the end
        if not in_permissions:
            new_lines.append("\n[permissions]\n")
            new_lines.append(new_permission_line + "\n")
            updated = True

        if updated:
            with open(perm_file_path, 'w') as f:
                f.writelines(new_lines)

    # Execute the set-permissions command
    command = [
        "sudo",
        "-u",
        "dcv",
        "dcv",
        "set-permissions",
        "--session",
        collab_session_name,
        "--file",
        perm_file_path
    ]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    if result.returncode != 0:
        return {"message": f"Error executing set-permissions: {result.stderr.strip()}"}, 500

    action = "created" if created else "updated"
    return {"message": f"Permission file '{perm_file_path}' {action} successfully."}, 200

def session_exists(session_name):
    try:
        response = get_list_sessions()
        data = response[0]
        data_parsed = json.loads(data.get_data(as_text=True))
        sessions = data_parsed.get("message", "")
        return f"Session: '{session_name}'" in sessions
    except Exception as e:
        print(f"Error checking session existence: {e}")
        return False
    
def create_response(message, stdout="", stderr="", return_code=200):
    response = {
        "message": message,
        "stdout": stdout,
        "stderr": stderr,
        "return_code": return_code
    }
    return jsonify(response), return_code

def get_session_type():
    try:
        settings = read_settings_conf()
        session_type = settings.get('session_type', 'virtual').strip().lower()
        if session_type not in ["console", "virtual"]:
            print(f"The session type >>> {session_type} <<< was not recognized from settings.conf file.")
            session_type = "virtual"  # Fallback value
    except Exception as e:
        # Although read_settings_conf already handles exceptions,
        # adding an extra layer can ensure robustness
        print(f"Error determining session_type: {e}")
        session_type = "virtual"
    return session_type

def is_positive_integer(value):
    try:
        int_value = int(value)
        return int_value > 0
    except (TypeError, ValueError):
        return False

def create_permission_file():
    collab_owner_username = request.args.get('collab_owner_username')
    collab_session_name = request.args.get('collab_session_name')
    response, status_code = manage_permission_file(collab_session_owner, collab_session_name, overwrite=True)
    return jsonify(response), status_code

def add_permission():
    collab_owner_username = request.args.get('collab_owner_username')
    collab_session_name = request.args.get('collab_session_name')
    collab_add_username = request.args.get('collab_add_username')
    new_line = f"{collab_add_username} allow display"
    response, status_code = manage_permission_file(collab_session_owner, collab_session_name, new_permission_line=new_line)
    return jsonify(response), status_code

@app.route('/remove-permission', methods=['POST'])
def remove_permission():
    collab_owner_username = request.args.get('collab_owner_username')
    collab_session_name = request.args.get('collab_session_name')
    collab_del_username = request.args.get('collab_del_username')

    if not collab_owner_username or not collab_session_name or not collab_del_username:
        return create_response("Missing one or more parameters: 'collab_owner_username', 'collab_session_name', 'collab_del_username'.", return_code=400)

    settings = read_settings_conf()
    session_perm_dir = settings.get('dcv_collab_sessions_permissions_dir', '')
    perm_file_path = f"{session_perm_dir}{collab_owner_username}.perm"
    
    if not os.path.isfile(perm_file_path):
        return create_response(f"Permission file '{perm_file_path}' does not exist.", return_code=404)

    try:
        with open(perm_file_path, 'r') as file:
            lines = file.readlines()

        with open(perm_file_path, 'w') as file:
            for line in lines:
                if line.strip() != f"{collab_del_username} allow display":
                    file.write(line)

        # Execute the command
        command = [
            "sudo",
            "dcv",
            "set-permissions",
            "--session",
            collab_session_name,
            "--file",
            perm_file_path
        ]

        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        if result.returncode != 0:
            return create_response(f"Error executing set-permissions: {result.stderr.strip()}", stderr=result.stderr, return_code=500)

        return create_response(f"Removed permission for '{collab_del_username}' successfully.", stdout=result.stdout, return_code=200)

    except Exception as e:
        return create_response(f"Error removing permission: {str(e)}", stderr=str(e), return_code=500)

@app.route('/approve-login', methods=['POST'])
def approve_login():
    try:
        collab_session_owner = request.args.get('collab_session_owner')
        collab_session_name = request.args.get('session_id', '').strip()
        collab_username = request.args.get('collab_username')
        number_of_connections = int(request.args.get('number_of_connections'))

        if not collab_session_owner or not collab_username or not number_of_connections:
            return create_response("Missing 'collab_session_owner' or 'collab_username' or 'number_of_connections' in request.", return_code=400)

        # Path to the send_prompt.sh script
        script_perm_prompt_path = "/usr/bin/dcv_collab_prompt"  # Update this path accordingly

        # Ensure the script exists
        if not os.path.isfile(script_perm_prompt_path):
            return create_response("Approval script not found on server.", return_code=500)

        # Set timeout in seconds
        settings = read_settings_conf()
        timeout = settings.get('dcv_collab_prompt_timeout', '')
        session_auto_creation_by_dcv = settings.get('session_auto_creation_by_dcv', '').strip()

        if not is_positive_integer(timeout):
            timeout = 23  # Fallback to default

        if session_auto_creation_by_dcv.strip().lower() == "false":
            if not collab_session_name:
                # get_first_session returns a tuple: (Flask response, status_code)
                resp, _ = get_first_session()
                data = json.loads(resp.get_data(as_text=True))
                collab_session_name = data.get("message")

            env = os.environ.copy()
            result = subprocess.run(
                [script_perm_prompt_path, collab_session_owner, collab_username, str(timeout)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                shell=False 
            )

            if result.returncode != 0:
                error_msg = result.stderr.strip() or "Unknown error occurred."
                return create_response(f"Error executing approval script: {error_msg}", stderr=result.stderr, return_code=500)

            approval = result.stdout.strip().lower()

            if approval == "true":
                if collab_session_owner == collab_username:
                    new_line = f"{collab_username} allow bultin"
                else:
                    new_line = f"{collab_username} allow display"
                
                response, status_code = manage_permission_file(collab_session_owner, collab_session_name, new_permission_line=new_line)
                if status_code != 200:
                    return create_response(response["message"], stderr=response.get("stderr", ""), return_code=status_code)

                return create_response(True, return_code=200)
            else:
                return create_response(False, return_code=200)
        else:
            env = os.environ.copy()

            result = subprocess.run(
                [script_perm_prompt_path, collab_session_owner, collab_username, str(timeout)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env, 
                shell=False
            )

            if result.returncode != 0:
                error_msg = result.stderr.strip() or "Unknown error occurred."
                return create_response(f"Error executing approval script: {error_msg}", stderr=result.stderr, return_code=500)

            approval = result.stdout.strip().lower()

            if approval == "true":
                if number_of_connections > 0:
                    new_line = f"{collab_username} allow display"
                else:
                    new_line = f"{collab_username} allow builtin"
                
                response, status_code = manage_permission_file(collab_session_owner, collab_session_name, new_permission_line=new_line)
                if status_code != 200:
                    return create_response(
                        response["message"],
                        stderr=response.get("stderr", ""),
                        return_code=status_code
                    )
                else:
                    return create_response(True, return_code=200)
            else:
                return create_response(False, return_code=200)
            
    except Exception as e:
        return create_response({"error": str(e)}, stderr=str(e), return_code=500)
    
@app.route('/check-collab-settings', methods=['GET'])
def check_collab_settings():
    try:
        settings = read_settings_conf()
        dcv_collab = settings.get('dcv_collab', '').lower()
        dcv_collab_session_name = settings.get('dcv_collab_session_name', '').strip()
        dcv_collab_session_type = settings.get('session_type', '').strip()
        session_auto_creation_by_dcv = settings.get('session_auto_creation_by_dcv', '').strip()

        if dcv_collab == 'true':
            # Check if the session exists
            if session_exists(dcv_collab_session_name):
                return create_response({"collab_enabled": True, "session_name": dcv_collab_session_name, "session_type": dcv_collab_session_type, "session_auto_creation_by_dcv": session_auto_creation_by_dcv})
            else:
                if not dcv_collab_session_name:
                    # get_first_session returns a tuple: (Flask response, status_code)
                    resp, _ = get_first_session()
                    data = json.loads(resp.get_data(as_text=True))
                    dcv_collab_session_name = data.get("message")

                if dcv_collab_session_name:
                    return create_response({"collab_enabled": True, "session_name": dcv_collab_session_name, "session_type": dcv_collab_session_type, "session_auto_creation_by_dcv": session_auto_creation_by_dcv})
                else:
                    return create_response({"collab_enabled": True, "session_name": None, "session_type": dcv_collab_session_type, "session_auto_creation_by_dcv": session_auto_creation_by_dcv})
        else:
            return create_response({"collab_enabled": False})
    except Exception as e:
        return create_response({"error": str(e)}, stderr=str(e), return_code=500)

@app.route('/get-session-owner', methods=['GET'])
def get_session_owner():
    try:
        session_name = request.args.get('session_name')
        if not session_name:
            return create_response("Missing session_name parameter. Please provide a session_name in the query string.", return_code=400)

        command = " ".join(["/usr/bin/dcv", "list-sessions", "--json"])
        process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output, error = process.communicate()

        if process.returncode != 0:
            return create_response("Error executing dcv list-sessions", stderr=error.decode(), return_code=500)

        sessions = json.loads(output.decode('utf-8'))
        
        for session in sessions:
            if session.get('id') == session_name:
                owner = session.get('owner')
                return create_response({"session_name": session_name, "owner": owner})

        return create_response(f"Session '{session_name}' not found.", return_code=404)
    
    except Exception as e:
        return create_response({"error": str(e)}, stderr=str(e), return_code=500)

@app.route('/collab-set-session-owner', methods=['POST'])
def collab_set_session_owner():
    global collab_session_owner
    session_id = request.args.get('session_id')
    session_owner = request.args.get('session_owner')

    if not session_id and not session_owner:
        return create_response("Missing owner or session_owner parameter.", return_code=400)

    collab_session_owner = session_owner.strip()

    response, status_code = manage_permission_file(collab_session_owner, session_id, overwrite=True)
    
    return create_response(
        {"collab_session_owner": collab_session_owner, "file_response": response["message"]},
        return_code=status_code
    )

@app.route('/collab-get-session-owner', methods=['GET'])
def collab_get_session_owner():
    global session_count_by_owner
    return create_response({"collab_session_owner": collab_session_owner}, return_code=200)

@app.route('/request_token', methods=['POST'])
def execute_ssh_command():
    data = request.get_json()
    user = data.get('user')
    host = data.get('host')
    port = data.get('port')
    time_token_expire = data.get('time_token_expire')
    private_key = data.get('private_key')

    if time_token_expire == None:
        time_token_expire = 3600

    command = '/usr/bin/dcv_get_token ' + time_token_expire

    try:
        key = paramiko.RSAKey.from_private_key(StringIO(private_key))
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(hostname=host, username=user, port=port, pkey=key)

        stdin, stdout, stderr = ssh.exec_command(command)
        output = stdout.read().decode()
        error = stderr.read().decode()

        ssh.close()

        return create_response(output, stdout=output, stderr=error)

    except Exception as e:
        return create_response(str(e), stderr=str(e), return_code=500)

@app.route('/count-sessions-by-owner', methods=['GET'])
def count_sessions(owner=None):
    try:
        if owner == None:
            owner = request.args.get('owner')
        if not owner:
            return create_response("Missing owner parameter. Please specify owner in the query string.", return_code=400)
        
        response = get_list_sessions() # tuple: json, http code
        data = response[0] # json part
        data_parsed = json.loads(data.get_data(as_text=True))
        stdout = data_parsed.get("stdout", "")
        
        # Count occurrences of the owner in the message
        count = stdout.count(f"Session: '{owner}'")

        return create_response(str(count), stdout=f"Count: {count}", return_code=200)
    except:
        return create_response("Error: Failed to run count-sessions", stderr=str(e), return_code=500)

@app.route('/create-session', methods=['GET'])
def create_session():
    owner = request.args.get('owner')
    if not owner:
        return create_response("Missing owner parameter. Please specify owner in the query string.", return_code=400)
    response = count_sessions(owner)
    data = response[0]
    data_parsed = json.loads(data.get_data(as_text=True))
    owner_count = int(data_parsed["message"])
    session_type = get_session_type()
    command = " ".join(["/usr/bin/dcv", "create-session", "--owner", owner, "--name", owner, "--type", session_type, owner])
    if owner_count == 0:
        try:
            process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
            output, error = process.communicate()
            if process.returncode == 0:
                return create_response("created", stdout=output.decode(), stderr=error.decode())
            else:
                return create_response("Error: Failed to run create-session", stdout=output.decode(), stderr=error.decode(), return_code=500)
        except Exception as e:
            return create_response("Error: Failed to run create-session", stderr=str(e), return_code=500)
    else:
        return create_response("already exist.", stdout=f"Count: {owner_count}", return_code=500)

@app.route('/close-session', methods=['GET'])
def close_session(session_id=None):
    session_id = request.args.get('session_id')
    if not session_id:
        return create_response("Missing session_id parameter. Please specify session_id in the query string.", return_code=400)

    command = " ".join(["dcv", "close-session", session_id])
    try:
        process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
        output, error = process.communicate()
        if process.returncode == 0:
            return create_response("closed", stdout=output.decode(), stderr=error.decode())
        else:
            return create_response("Error: Failed to run close-session", stdout=output.decode(), stderr=error.decode(), return_code=500)
    except Exception as e:
        return create_response("Error: Failed to run close-session", stderr=str(e), return_code=500)

@app.route('/list-connections', methods=['GET'])
def list_connections(owner=None):
    owner = request.args.get('owner')
    if not owner:
        return create_response("Missing owner parameter. Please specify owner in the query string.", return_code=400)
    command = " ".join(["dcv", "list-connections", owner])
    try:
        process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
        output, error = process.communicate()
        output = output.decode("utf-8")
        error = error.decode("utf-8")
        return create_response(output, stdout=output, stderr=error)
    except Exception as e:
        return create_response("Error: Failed to list connections", stderr=str(e), return_code=500)

@app.route('/check-session-timedout', methods=['GET'])
def check_session_timedout(session_id=None):
    session_id = request.args.get('session_id')

    settings = read_settings_conf()
    session_timeout = int(settings.get('session_timeout', ''))

    # fallback value, disabling the timedout check
    if not session_timeout:
        session_timeout = 0

    if session_timeout == 0:
        return create_response(
            "Session timedout check is disabled because session_timeout is equal zero.",
            stdout=f"Inactive duration: {inactive_duration} seconds",
            stderr=error
        )

    if not session_id:
        return create_response("Missing session_id parameter. Please specify owner in the query string.", return_code=400)
    
    command= " ".join(["dcv", "describe-session", session_id, "--json"])


    try:
        process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
        output, error = process.communicate()
        output = output.decode("utf-8")
        error = error.decode("utf-8")

        if process.returncode != 0:
            return create_response("Error: Failed to describe session", stdout=output, stderr=error, return_code=500)

        data = json.loads(output)
        num_connections = data.get("num-of-connections", 0)
        creation_time_str = data.get("creation-time")
        disconnection_time_str = data.get("last-disconnection-time")

        # Use disconnection time if available; otherwise, use creation time as fallback.
        last_activity_str = disconnection_time_str if disconnection_time_str else creation_time_str
        
        # define the time format string
        format_string = "%Y-%m-%dT%H:%M:%S.%fZ"
        last_activity = datetime.strptime(last_activity_str, format_string)
        
        # Calculate inactivity using the current time
        current_time = datetime.utcnow()
        inactive_duration = (current_time - last_activity).total_seconds()

        if num_connections == 0:
            if inactive_duration > session_timeout:
                return close_session(session_id)
            else:
                return create_response(
                    "There are no users connected, but the session has not been inactive long enough.",
                    stdout=f"Inactive duration: {inactive_duration} seconds",
                    stderr=error
                )
        else:
            return create_response(
                "There are users still connected under DCV session.",
                stdout=output,
                stderr=error
            )
    except Exception as e:
        return create_response("Error: Failed to check session timeout", stderr=str(e), return_code=500)

@app.route('/list-sessions-owners', methods=['GET'])
def list_sessions_owners():
    try:
        # Call get_list_sessions_json to get the sessions as JSON.
        response, status_code = get_list_sessions_json()
        if status_code != 200:
            return response, status_code

        # Parse the response data to extract the list of sessions.
        data = json.loads(response.get_data(as_text=True))
        sessions = data.get("message", [])
        
        # Extract the "owner" value from each session.
        owners = []
        for session in sessions:
            owner = session.get("owner")
            if owner:
                owners.append(owner)

        return create_response(owners, stdout=json.dumps(owners), return_code=200)
    except Exception as e:
        return create_response("Error: Failed to list session owners", stderr=str(e), return_code=500)

@app.route('/get-first-session', methods=['GET'])
def get_first_session():
    try:
        # Get the list-sessions response using the existing function
        response, status_code = get_list_sessions()
        # Parse the JSON data returned by get_list_sessions
        data = json.loads(response.get_data(as_text=True))
        message = data.get("message", "")
        
        # Split the message by newline to get individual session lines
        lines = message.splitlines()
        session_name = None  # Default null
                
        if lines:
            first_line = lines[0]
            # Use regex to match the session name inside single quotes after "Session: "
            match = re.search(r"Session: '([^']+)'", first_line)
            if match:
                session_name = match.group(1)
        
        # Return the session name; if session_name is None, jsonify will output null
        return create_response(session_name, return_code=200)
    except Exception as e:
        return create_response("Error retrieving first session", stderr=str(e), return_code=500)

@app.route('/list-sessions', methods=['GET'])
def get_list_sessions():
    try:
        command = " ".join(["dcv", "list-sessions"])
        process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
        output, error = process.communicate()
        output = output.decode("utf-8")
        error = error.decode("utf-8")

        return create_response(output, stdout=output, stderr=error)
    except Exception as e:
        return create_response("Error: Failed to run 'dcv list-sessions'", stderr=str(e), return_code=500)

@app.route('/list-sessions-json', methods=['GET'])
def get_list_sessions_json():
    try:
        command = " ".join(["dcv", "list-sessions", "--json"])
        process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
        output, error = process.communicate()
        output = output.decode("utf-8")
        error = error.decode("utf-8")

        try:
            json_output = json.loads(output)
        except json.JSONDecodeError:
            return create_response("Error: Failed to parse JSON output", stderr="Invalid JSON format", return_code=500)

        return create_response(json_output, stdout=output, stderr=error, return_code=200)
    except Exception as e:
        return create_response("Error: Failed to run 'dcv list-sessions'", stderr=str(e), return_code=500)

@app.route('/', methods=['GET'])
def get_data():
    return create_response("This is an API used to manage your DCV services.")

if __name__ == '__main__':
    app.run(debug=False)
