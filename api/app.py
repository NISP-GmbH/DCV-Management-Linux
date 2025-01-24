from flask import Flask, request, jsonify
import subprocess
import os
import json
from datetime import datetime

app = Flask(__name__)

def read_settings_conf():
    # Define fallback/default values
    settings = {
        "session_type": "virtual",
        "dcv_collab": "false",
        "dcv_cllab_prompt_timeout": 20,
        "dcv_collab_session_name": ""
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
    """
    Validates if the provided value is a positive integer.
    Returns True if valid, False otherwise.
    """
    try:
        int_value = int(value)
        return int_value > 0
    except (TypeError, ValueError):
        return False

@app.route('/approve-login', methods=['POST'])
def approve_login():
    """
    Endpoint to send a login approval request to a user.
    Expects JSON payload with 'username'.
    Returns true if approved, false otherwise.
    """
    try:
        username = request.args.get('username')
        collab_username = request.args.get('collab_username')
        
        if not username or not collab_username:
            return create_response("Missing 'username' or 'collab_username' in request.", return_code=400)

        # Path to the send_prompt.sh script
        script_path = "/usr/bin/dcv_collab_prompt"  # Update this path accordingly
        
        # Ensure the script exists
        if not os.path.isfile(script_path):
            return create_response("Approval script not found on server.", return_code=500)
        
        # Set timeout in seconds
        settings = read_settings_conf()
        timeout = settings.get('dcv_collab_prompt_timeout', '')

        if not is_positive_integer(timeout):
            timeout = 23  # Fallback to default
 
        # Enhanced logging and debugging
        print(f"Executing script with params: username={username}, collab_username={collab_username}, timeout={timeout}")

        # Use full environment variables
        env = os.environ.copy()     

        # Execute the script as the target user
        # Assumes the Flask app has necessary permissions to execute as other users
        # You might need to configure sudoers to allow this without password
        # Execute the script with full path and environment
        result = subprocess.run(
            [script_path, username, collab_username, str(timeout)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,  # Pass full environment
            shell=False  # Recommended for security
        )
        
        # More detailed logging
        print(f"Script Exit Code: {result.returncode}")
        print(f"Script STDOUT: {result.stdout}")
        print(f"Script STDERR: {result.stderr}")

        # Check for errors in execution
        if result.returncode != 0:
            error_msg = result.stderr.strip() or "Unknown error occurred."
            return create_response(f"Error executing approval script: {error_msg}", stderr=result.stderr, return_code=500)
        
        # Parse the script's output
        approval = result.stdout.strip().lower()
        
        if approval == "true":
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

        if dcv_collab == 'true' and dcv_collab_session_name:
            # Check if the session exists
            if session_exists(dcv_collab_session_name):
                return create_response({"collab_enabled": True, "session_name": dcv_collab_session_name})
            else:
                return create_response({"collab_enabled": False, "reason": "Session not found."})
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
    response = count_sessions(owner) # tuple: json, http code
    data = response[0] # json part
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
def close_session(owner=None):
    owner = request.args.get('owner')
    if not owner:
        return create_response("Missing owner parameter. Please specify owner in the query string.", return_code=400)
    
    response = count_sessions(owner) # tuple: json, http code
    data = response[0] # json part
    data_parsed = json.loads(data.get_data(as_text=True))
    owner_count = int(data_parsed["message"])

    if owner_count > 0:
        command = " ".join(["dcv", "close-session", owner])
        try:
            process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
            output, error = process.communicate()
            if process.returncode == 0:
                return create_response("closed", stdout=output.decode(), stderr=error.decode())
            else:
                return create_response("Error: Failed to run close-session", stdout=output.decode(), stderr=error.decode(), return_code=500)
        except Exception as e:
            return create_response("Error: Failed to run close-session", stderr=str(e), return_code=500)
    else:
        return create_response("No session found to be closed.")

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
def check_session_timedout(owner=None):
    owner = request.args.get('owner')
    if not owner:
        return create_response("Missing owner parameter. Please specify owner in the query string.", return_code=400)
    command= " ".join(["dcv", "describe-session", owner, "--json"])

    try:
        process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
        output, error = process.communicate()
        output = output.decode("utf-8")
        error = error.decode("utf-8")

        if process.returncode == 0:
            data = json.loads(output)
            num_connections = data["num-of-connections"]
            creation_time_str = data["creation-time"]
            disconnection_time_str = data["last-disconnection-time"]
            if not disconnection_time_str:
                disconnection_time_str = data["creation-time"]
            format_string = "%Y-%m-%dT%H:%M:%S.%fZ"
            creation_time = datetime.strptime(creation_time_str, format_string)
            disconnection_time = datetime.strptime(disconnection_time_str, format_string)
            time_difference = disconnection_time - creation_time
            difference_in_seconds = time_difference.total_seconds()

            if num_connections == 0:
                if difference_in_seconds > 1800:
                    response = close_session(owner)
                    return response
                else:
                    return create_response("There are no users connected, but the time to timeout did not reach yet.", stdout=output, stderr=error)
            else:
                return create_response("There are users still connected under DCV session.", stdout=output, stderr=error)
        else:
            return create_response("Error: Failed to describe session", stdout=output, stderr=error, return_code=500)
    except Exception as e:
        return create_response("Error: Failed to check session timeout", stderr=str(e), return_code=500)

@app.route('/list-sessions-owners', methods=['GET'])
def list_sessions_owners():
    try:
        response = get_list_sessions()
        response_code = response[1]
        data = response[0]
        data_parsed_json = json.loads(data.get_data(as_text=True))
        message = data_parsed_json["message"]
        lines = message.splitlines()
        owners = []
        for line in lines:
            parts = line.split()
            owners.append(parts[1].strip("'"))
        return create_response(owners, stdout=json.dumps(owners))
    except Exception as e:
        return create_response("Error: Failed to list session owners", stderr=str(e), return_code=500)
    
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

@app.route('/', methods=['GET'])
def get_data():
    return create_response("This is an API used to manage your DCV services.")

if __name__ == '__main__':
    app.run(debug=False)  # Set debug=False for production
