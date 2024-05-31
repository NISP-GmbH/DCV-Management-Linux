from flask import Flask, request, jsonify
import subprocess
import os
import json
from datetime import datetime

app = Flask(__name__)

return_root = {"return": "This is an API used to manage your DCV services."}

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

        return { 'message': output}, 200

    except Exception as e:
        return { 'message': str(e) }, 500

@app.route('/count-sessions-by-owner', methods=['GET'])
def count_sessions(owner=None):
    try:
        if owner == None:
            owner = request.args.get('owner')
        if not owner:
            return jsonify({"message": "Missing owner parameter. Please specify owner in the query string."}), 400
        
        response = get_list_sessions() # tuple: json, http code
        data = response[0] # json part
        data_parsed = data.get_data(as_text=True)
        count = data_parsed.count('Session: \'' + owner + '\'')

        return jsonify({"message": count}), 200
    except:
        return jsonify({"message": "Error: Failed to run count-sessions"}), 500

@app.route('/create-session', methods=['GET'])
def get_console_type():
    try:
        with open('/etc/dcv-management/settings.conf', 'r') as file:
            for line in file:
                if line.startswith('console_type='):
                    console_type = line.split('=')[1].strip()
                    break
        if console_type not in ["console", "virtual"]:
            print("The console type >>> " + console_type + " <<< was not recognized from settings.conf file.")
            console_type = "virtual" # fallback value
    except Exception as e:
        # Log the exception if needed
        print(f"Error reading console_type: {e}")
        console_type = "virtual"
    return console_type

def create_session():
    owner = request.args.get('owner')
    if not owner:
        return jsonify({"message": "Missing owner parameter. Please specify owner in the query string."}), 400
    response = count_sessions(owner) # tuple: json, http code
    data = response[0] # json part
    data_parsed = json.loads(data.get_data(as_text=True))
    owner_count = int(data_parsed["message"])
    console_type = get_console_type()
    command = " ".join(["/usr/bin/dcv", "create-session", "--owner", owner, "--name", owner, "--type", console_type, owner])
    if owner_count == 0:
        try:
            process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
            output, error = process.communicate()  # Capture stdout and stderr
        except subprocess.CalledProcessError as error:
            print("Error:", error)  # Print the error object
        if process.returncode == 0:
            return jsonify({"message": "created"}), 200
        else:
            return jsonify({"message": "Error: Failed to run create-session"}), 500
    else:
        return jsonify({"message": "already exist.", "count": owner_count}), 500

@app.route('/close-session', methods=['GET'])
def close_session(owner=None):
    owner = request.args.get('owner')
    if not owner:
        return jsonify({"message": "Missing owner parameter. Please specify owner in the query string."}), 400

    response = count_sessions(owner) # tuple: json, http code
    data = response[0] # json part
    data_parsed = json.loads(data.get_data(as_text=True))
    owner_count = int(data_parsed["message"])

    if owner_count > 0:
        command= " ".join(["dcv", "close-session", owner])
        try:
            process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
            output, error = process.communicate()  # Capture stdout and stderr
        except:
                print("Error:", error)
        if process.returncode == 0:
            return jsonify({"message": "closed"}), 200
        else:
            return jsonify({"message": "Error: Failed to run close-session"}), 500
    else:
        return jsonify({"message": "No session found to be closed."}), 200

@app.route('/list-connections', methods=['GET'])
def list_connections(owner=None):
    owner = request.args.get('owner')
    if not owner:
        return jsonify({"message": "Missing owner parameter. Please specify owner in the query string."}), 400
    command= " ".join(["dcv", "list-connections", owner])
    try:
        process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
        output, error = process.communicate()  # Capture stdout and stderr
    except subprocess.CalledProcessError as error:
            print("Error:", error)
    output = output.decode("utf-8")
    
    return jsonify({"message": output}), 20

@app.route('/check-session-timedout', methods=['GET'])
def check_session_timedout(owner=None):
    owner = request.args.get('owner')
    if not owner:
        return jsonify({"message": "Missing owner parameter. Please specify owner in the query string."}), 400
    command= " ".join(["dcv", "describe-session", owner, "--json"])

    try:
        process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
        output, error = process.communicate()  # Capture stdout and stderr
    except subprocess.CalledProcessError as error:
        print("Error:", error)

    if process.returncode == 0:
        data = json.loads(output)
        num_connections = data["num-of-connections"]
        creation_time_str = data["creation-time"]
        disconnection_time_str = data["last-disconnection-time"]
        if not disconnection_time_str: # if empty, there are no disconnections yet
            disconnection_time_str = data["creation-time"]
        format_string = "%Y-%m-%dT%H:%M:%S.%fZ"
        creation_time = datetime.strptime(creation_time_str, format_string)
        disconnection_time = datetime.strptime(disconnection_time_str, format_string)
        time_difference = disconnection_time - creation_time
        difference_in_seconds = time_difference.total_seconds()

        if num_connections == 0:
            if difference_in_seconds > 1800:
                response = close_session(owner)
                response_code = response[1]
                data = response[0]
                return data
            else:
                return jsonify({"message": "There are no users connected, but the time to timedout did not reach yet."}), 200
        else:
            return jsonify({"message": "There are users still connected under DCV session."}), 200
    else:
        return jsonify({"message": output.decode("utf-8")})

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
        return jsonify({"message": owners}), 200
        
    except subprocess.CalledProcessError:
        return jsonify({"message": "Error: Failed to run 'dcv list-sessions"}), 500
    
@app.route('/list-sessions', methods=['GET'])
def get_list_sessions():
    try:
        command= " ".join(["dcv", "list-sessions"])
        try:
            process = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
            output, error = process.communicate()  # Capture stdout and stderr
        except subprocess.CalledProcessError as error:
            print("Error:", error)

        output = output.decode("utf-8")

        return jsonify({"message": output}), 200
    except subprocess.CalledProcessError:
        return jsonify({"message": "Error: Failed to run 'dcv list-sessions"}), 500

@app.route('/', methods=['GET'])
def get_data():
    return jsonify(return_root)

if __name__ == '__main__':
    app.run(debug=False)  # Set debug=False for production
