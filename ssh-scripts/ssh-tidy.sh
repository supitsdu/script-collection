#!/bin/sh
# Any copyright is dedicated to the Public Domain.
# https://creativecommons.org/publicdomain/zero/1.0/

# Default directory containing SSH keys
SSH_KEYS_DIR="$HOME/.ssh"

# List of SSH keys to be managed
SSH_TIDY_KEYS="id_ed25519 id_ecdsa id_rsa"

# Verbose flag
VERBOSE=0

# Log file
LOG_FILE="$HOME/.cache/ssh_tidy.log"

# Function to log debug messages
debug_log() {
    if [ $VERBOSE -eq 1 ]; then
        echo "$1"
    fi
    echo "$(date): $1" >>"$LOG_FILE"
}

# Function to check if ssh-agent is running
is_ssh_agent_running() {
    if [ -n "$SSH_AGENT_PID" ] && ps -p "$SSH_AGENT_PID" >/dev/null 2>&1; then
        return 0 # ssh-agent is running
    else
        return 1 # ssh-agent is not running
    fi
}

# Function to check if a file exists
is_file() {
    if [ -f "$1" ]; then
        return 0 # File exists
    else
        return 1 # File does not exist
    fi
}

# Function to check if a key is already added to ssh-agent
is_key_added() {
    key_file="$1"
    key_pub_file="${1}.pub"

    if [ ! -f "$key_file" ] || [ ! -f "$key_pub_file" ]; then
        return 0 # Key or its public part does not exist
    fi

    # Extract the fingerprint of the public key file
    key_fingerprint=$(ssh-keygen -lf "$key_pub_file" | awk '{print $2}')
    [ -n "$key_fingerprint" ] || return 0 # Fingerprint extraction failed

    # Check if the fingerprint is in the list of added keys
    if ssh-add -l | grep -q "$key_fingerprint"; then
        return 0 # Key is already added, return zero
    else
        return 1 # Key is not added, return error
    fi
}

# Function to add a key to ssh-agent
add_ssh_key() {
    echo "Adding keys.."
    key_file="$1"

    if ssh-add "$key_file"; then
        debug_log "Added key: $key_file"
        return 0 # Key added successfully
    else
        debug_log "Failed to add key: $key_file"
        return 1 # Failed to add key
    fi
}

# Function to get filenames of keys
get_keys_filenames() {
    keys=""
    # Loop through the list of keys and check if they exist
    for file in $SSH_TIDY_KEYS; do
        priv_file="${SSH_KEYS_DIR}/$file"
        pub_file="${priv_file}.pub"
        if is_file "$priv_file" && is_file "$pub_file"; then
            if [ -n "$keys" ]; then
                keys="$keys $priv_file"
            else
                keys="$priv_file"
            fi
        fi
    done

    echo "$keys"
}

# Function to list all keys in .ssh directory
list_all_keys() {
    echo "Available SSH keys in '$SSH_KEYS_DIR':"
    echo
    for key in $(eval ls "$SSH_KEYS_DIR" | grep -E 'id_(ed25519|ecdsa|rsa)$'); do
        if is_key_added "$SSH_KEYS_DIR/$key"; then
            echo " » File: '$key' - Identity: OK"
        else
            echo " » File: '$key' - Identity: Unknown"
        fi
    done
}

# Function to check environment dependencies
check_dependencies() {
    for cmd in ssh-add ssh-agent ssh-keygen; do
        if ! command -v $cmd >/dev/null 2>&1; then
            echo "Error: $cmd is not installed."
            exit 1
        fi
    done
}

# Function to parse command line options
parse_options() {
    while getopts "a:d:slvkh" opt; do
        case $opt in
        a)
            SSH_TIDY_KEYS="$SSH_TIDY_KEYS $OPTARG"
            ;;
        d)
            SSH_KEYS_DIR="$OPTARG"
            ;;
        s)
            if is_ssh_agent_running; then
                echo "The SSH agent is running."
                exit 0
            else
                echo "The SSH agent is not running."
                exit 1
            fi
            ;;
        l)
            list_all_keys
            exit 0
            ;;
        v)
            VERBOSE=1
            ;;
        k)
            if is_ssh_agent_running; then
                eval "$(ssh-agent -k)"
                echo "ssh-agent stopped."
                exit 0
            else
                echo "ssh-agent is not running."
                exit 1
            fi
            ;;
        h | *)
            echo "Usage:"
            echo
            echo "    $0 [ -a key | -d directory | -s | -l | -v | -k | -h ]"
            echo
            echo "Options:"
            echo
            echo "    -a key        Add an additional key filename."
            echo "    -d directory  Specify a custom directory for SSH keys."
            echo "    -s            Check if the ssh-agent is running."
            echo "    -l            List the location of all added SSH identities."
            echo "    -v            Enable verbose mode."
            echo "    -k            Kill the ssh-agent."
            echo "    -h            Show this help message."
            exit 1
            ;;
        esac
    done
}

# Main function to manage SSH keys
main() {
    # Check environment dependencies
    check_dependencies

    # Check if ssh-agent is running, if not, start it
    if ! is_ssh_agent_running; then
        eval "$(ssh-agent)" || {
            echo "Failed to start SSH Agent. No keys will be added."
            return 1
        }
    fi

    # Loop through each key and check/add it to ssh-agent
    for key in $(get_keys_filenames); do
        if ! is_key_added "$key"; then
            add_ssh_key "$key"
        fi
    done
}

# Parse command line options
parse_options "$@"

# Execute the main function
main
