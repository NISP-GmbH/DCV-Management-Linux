#!/bin/bash

export GDK_DEBUG=none

# Check for minimum parameters.
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <username> <notification_type> <title> <text> [buttons]"
    exit 1
fi

TARGET_USER="$1"
NOTIF_TYPE="$2"
TITLE="$3"
TEXT="$4"

if [ "$#" -ge 5 ]; then
    BUTTONS_STRING="$5"
    # Split the string using the ASCII Unit Separator as delimiter.
    IFS=$'\x1f' read -r -a BUTTONS <<< "$BUTTONS_STRING"
else
    BUTTONS=()
fi

NUM_BUTTONS=${#BUTTONS[@]}

# Function to retrieve the GNOME session environment variables for the target user.
get_user_session_info() {
    local user="$1"
    local pid
    pid=$(pgrep -u "$user" -x gnome-session || pgrep -u "$user" -x gnome-shell)
    if [ -z "$pid" ]; then
        echo "Error: Could not find GNOME session for user '$user'" >&2
        exit 1
    fi

    local pid_count
    pid_count=$(echo "$pid" | wc -w)
    if [ "$pid_count" -gt 1 ]; then
        echo "Error: Multiple GNOME sessions found for user '$user'" >&2
        exit 1
    fi

    # Read environment variables from the process's environ file.
    local environ
    environ=$(tr '\0' '\n' < /proc/"$pid"/environ)

    local display
    display=$(echo "$environ" | grep '^DISPLAY=' | cut -d= -f2-)
    local dbus
    dbus=$(echo "$environ" | grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)
    local xauthority
    xauthority=$(echo "$environ" | grep '^XAUTHORITY=' | cut -d= -f2-)

    # Fallback for XAUTHORITY if not found.
    if [ -z "$xauthority" ]; then
        xauthority="/home/$user/.Xauthority"
    fi

    if [ -z "$display" ] || [ -z "$dbus" ] || [ -z "$xauthority" ]; then
        echo "Error: Required environment variable missing for user '$user'" >&2
        exit 1
    fi

    echo "$display" "$dbus" "$xauthority"
}

# Retrieve and export GNOME session variables for the target user.
read DISPLAY_VAR DBUS_SESSION_BUS_ADDRESS_VAR XAUTHORITY_VAR < <(get_user_session_info "$TARGET_USER")
export DISPLAY="$DISPLAY_VAR"
export DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS_VAR"
export XAUTHORITY="$XAUTHORITY_VAR"

# Display the notification based on the number of button labels.
result=""
if [ "$NUM_BUTTONS" -eq 0 ]; then
    # No buttons provided: use a simple info dialog.
    zenity --info --title="$TITLE" --text="$TEXT" --width=400 --height=150 2>/dev/null
    rc=$?
    if [ $rc -eq 0 ]; then
        result="true"
    else
        result="false"
    fi
elif [ "$NUM_BUTTONS" -eq 1 ]; then
    # One button provided: show an info dialog with a custom OK label.
    zenity --info --title="$TITLE" --text="$TEXT" --ok-label="${BUTTONS[0]}" --width=400 --height=150 2>/dev/null
    rc=$?
    if [ $rc -eq 0 ]; then
        result="${BUTTONS[0]}"
    else
        result="false"
    fi
elif [ "$NUM_BUTTONS" -eq 2 ]; then
    # Two buttons provided: show a question dialog with custom OK and Cancel labels.
    zenity --question --title="$TITLE" --text="$TEXT" --ok-label="${BUTTONS[0]}" --cancel-label="${BUTTONS[1]}" --width=400 --height=150 2>/dev/null
    rc=$?
    if [ $rc -eq 0 ]; then
        result="${BUTTONS[0]}"
    else
        result="${BUTTONS[1]}"
    fi
else
    # More than two buttons provided: use a list dialog to allow the user to choose one option.
    result=$(zenity --list --title="$TITLE" --text="$TEXT" --column="Options" "${BUTTONS[@]}" --hide-header --width=400 --height=300 2>/dev/null)
    rc=$?
    if [ $rc -ne 0 ]; then
        result="false"
    fi
fi

echo "$result"
exit 0
