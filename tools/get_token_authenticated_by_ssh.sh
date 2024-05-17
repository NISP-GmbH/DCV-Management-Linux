#!/bin/bash

# vars
token_expiration_time_in_seconds=$1

# Please configure these SSH infos:
ssh_host="myhostnameorip"
ssh_user="myuser"
ssh_port="22"
ssh_private_key="~/.ssh/id_rsa"


response=$(ssh -o StrictHostKeyChecking=no -i $ssh_private_key -u $ssh_user -h $ssh_host -p $ssh_port "dcv_get_token $token_expiration_time_in_seconds"

echo "The token created was >>> $response <<< and the time to expire was >>> $token_expiration_time_in_seconds <<< seconds."
echo "Now please, using your dcv client, configure the host as these examples:"
echo "dcvserverip:8443#123456"
echo "dcvdomain.com:8443#123456"
echo "Replace first part with IP/domain. The second part with your DCV Server port. The third part with your token."
echo "Note: After token expiration, you need to ask for a new token!"
