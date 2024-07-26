from flask import Flask, request, jsonify
import subprocess
import os
import json
from datetime import datetime

app = Flask(__name__)

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
        with open('/etc/dcv-management/settings.conf', 'r') as file:
            for line in file:
                if line.startswith('session_type='):
                    session_type = line.split('=')[1].strip()
                    break
        if session_type not in ["console", "virtual"]:
            print("The console type >>> " + session_type + " <<< was not recognized from settings.conf file.")
            session_type = "virtual" # fallback value
    except Exception as e:
        # Log the exception if needed
        print(f"Error reading session_type: {e}")
        session_type = "virtual"
    return session_type

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
