#!/bin/sh
# Any copyright is dedicated to the Public Domain.
# https://creativecommons.org/publicdomain/zero/1.0/

# Directory containing SSH keys
SSH_KEYS_DIR="$HOME/.ssh"

# List of SSH keys to be managed
SSH_TIDY_KEYS="id_ed25519 id_ecdsa id_rsa"

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
        return 1 # Key is already added
    else
        return 0 # Key is not added
    fi
}

# Function to add a key to ssh-agent
add_ssh_key() {
    key_file="$1"

    if ssh-add "$key_file"; then
        return 0 # Key added successfully
    else
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

# Function to parse command line options
parse_options() {
    while getopts "a: s l h" opt; do
        case $opt in
        a)
            SSH_TIDY_KEYS="$SSH_TIDY_KEYS $OPTARG"
            ;;
        s)
            if is_ssh_agent_running; then
                echo "ssh-agent is running."
                exit 0
            else
                echo "ssh-agent is not running."
                exit 1
            fi
            ;;
        l)
            echo "Location of the added SSH identities:"
            for key in $(get_keys_filenames); do
                if is_key_added "$key"; then
                    echo "$key"
                fi
            done
            exit 0
            ;;
        h | *)
            echo "Usage:"
            echo
            echo "    $0 [ -a keys_list | -s | -l ]"
            echo
            echo "Options:"
            echo
            echo "    -a keys_list  Additional keys filenames. (Space separated)"
            echo "    -s            Check if the ssh-agent is running."
            echo "    -l            List the location of all added SSH identities."
            exit 1
            ;;
        esac
    done
}

# Main function to manage SSH keys
main() {
    # Check if ssh-agent is running, if not, start it
    if ! is_ssh_agent_running; then
        eval "$(ssh-agent -s)" >/dev/null 2>&1 || {
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
