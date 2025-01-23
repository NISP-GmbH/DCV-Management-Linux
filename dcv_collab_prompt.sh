#!/bin/bash

# ----------------------------
# Usage:
#   send_prompt.sh <username> <collab_username> [<timeout_in_seconds>]
#
# Parameters:
#   username           - The user to receive the approval prompt.
#   collab_username    - The user requesting the authorization.
#   timeout_in_seconds - (Optional) Timeout duration in seconds. Defaults to 20 if invalid or not provided.
# ----------------------------

# ----------------------------
# Function Definitions
# ----------------------------

# Function to validate that TIMEOUT is a positive integer
is_positive_integer() {
    local re='^[1-9][0-9]*$'
    [[ "$1" =~ $re ]]
}

# Function to retrieve DISPLAY, DBUS_SESSION_BUS_ADDRESS, and XAUTHORITY for the user
get_user_session_info() {
    local user="$1"

    # Attempt to find the PID of gnome-session or gnome-shell for the exact user
    local pid
    pid=$(pgrep -u "$user" -x gnome-session || pgrep -u "$user" -x gnome-shell)

    if [ -z "$pid" ]; then
        echo "Error: Could not find GNOME session for user '$user'." >&2
        exit 1
    fi

    # Check if multiple PIDs are returned
    pid_count=$(echo "$pid" | wc -w)
    if [ "$pid_count" -gt 1 ]; then
        echo "Error: Multiple GNOME sessions found for user '$user'." >&2
        exit 1
    fi

    # Extract environment variables from the PID
    local environ
    environ=$(tr '\0' '\n' < /proc/"$pid"/environ)

    local display
    display=$(echo "$environ" | grep '^DISPLAY=' | cut -d= -f2-)
    local dbus
    dbus=$(echo "$environ" | grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)
    local xauthority
    xauthority=$(echo "$environ" | grep '^XAUTHORITY=' | cut -d= -f2-)

    # Fallback to default XAUTHORITY if not found
    if [ -z "$xauthority" ]; then
        xauthority="/home/$user/.Xauthority"
    fi

    if [ -z "$display" ] || [ -z "$dbus" ] || [ -z "$xauthority" ]; then
        echo "Error: DISPLAY, DBUS_SESSION_BUS_ADDRESS, or XAUTHORITY not found for user '$user'." >&2
        exit 1
    fi

    echo "$display" "$dbus" "$xauthority"
}

# ----------------------------
# Argument Parsing and Validation
# ----------------------------

# Ensure at least two arguments (username and collab_username) are provided
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <username> <collab_username> [<timeout_in_seconds>]" >&2
    exit 1
fi

USERNAME="$1"
COLLAB_USERNAME="$2"
TIMEOUT="${3:-20}"  # Default to 20 seconds if not provided

# Validate TIMEOUT
if ! is_positive_integer "$TIMEOUT"; then
    echo "Warning: Invalid timeout value '$TIMEOUT'. Using default timeout of 20 seconds." >&2
    TIMEOUT=20
fi

# ----------------------------
# Retrieve User Session Information
# ----------------------------

read DISPLAY_VAR DBUS_SESSION_BUS_ADDRESS_VAR XAUTHORITY_VAR < <(get_user_session_info "$USERNAME")

# Export environment variables for GUI applications
export DISPLAY="$DISPLAY_VAR"
export DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS_VAR"
export XAUTHORITY="$XAUTHORITY_VAR"

# ----------------------------
# Display Approval Dialog Using Zenity
# ----------------------------

# Check if Zenity is installed
if ! command -v zenity &> /dev/null; then
    echo "Error: Zenity is not installed. Please install Zenity to proceed." >&2
    exit 1
fi

# Define log file path
LOG_FILE="/var/log/send_prompt.log"

# Construct the approval message
APPROVAL_MESSAGE="User '$COLLAB_USERNAME' is requesting authorization to log in. Do you approve this request?"

# Display the dialog
zenity --question \
       --title="Login Approval" \
       --text="$APPROVAL_MESSAGE" \
       --timeout="$TIMEOUT" \
       --ok-label="Approve" \
       --cancel-label="Deny" \
       --width=400 \
       --height=150

# Capture the exit status
EXIT_STATUS=$?

# Determine approval based on exit status
case $EXIT_STATUS in
    0)
        # User clicked "Approve"
        approval="true"
        ;;
    5)
        # Timeout occurred
        approval="false"
        ;;
    *)
        # User clicked "Deny" or closed the dialog
        approval="false"
        ;;
esac

# Log the response
echo "$(date) - Target User: $USERNAME - Requesting User: $COLLAB_USERNAME - Timeout: $TIMEOUT - Approval: $approval" >> "$LOG_FILE"

# Output the result
echo "$approval"

exit 0
