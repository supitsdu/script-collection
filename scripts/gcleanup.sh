#!/bin/sh
# Any copyright is dedicated to the Public Domain.
# https://creativecommons.org/publicdomain/zero/1.0/

# ANSI color codes
RESET='\033[0m'
BOLD='\033[1m'
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
BLUE='\033[34m'

# Network test address
NET_TEST_URL="https://1.0.0.1/"

# Function to handle messages
log_message() {
    color="$1"
    prefix="$2"
    message="$3"
    echo "${color}[${prefix}] $message${RESET}"
    echo "[$prefix] $message" >>.git/cleanup_log.txt
}

# Functions for different message types
log_info() { log_message "$BLUE" "INFO" "$1"; }
log_warn() { log_message "$YELLOW" "WARNING" "$1"; }
log_success() { log_message "$GREEN" "SUCCESS" "$1"; }
log_error() { log_message "$RED" "ERROR" "$1"; }

# Function to prompt the user
log_prompt() {
    printf "${BOLD}%s${RESET} " "$1"
}

# Function to prompt user for input
prompt() {
    read -r response
    response=${response:-n}
    echo "$response" | tr '[:upper:]' '[:lower:]'
}

# Function to generate timestamp
generate_timestamp() {
    date +"%Y-%m-%d_%H-%M-%S"
}

# Function to ensure we are in a git repository
check_git_repository() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        log_error "Not a git repository. Exiting."
        exit 1
    }
}

# Function to get the current branch
get_current_branch() {
    git branch --show-current || {
        log_error "Failed to retrieve the current branch."
        exit 1
    }
}

# Function to check if there are changes to stash
needs_stash() {
    git diff-index --quiet HEAD -- || echo "yes"
}

# Function to stash changes
stash_changes() {
    timestamp=$(generate_timestamp)
    stash_name="Backup of uncommitted changes - Branch: $1 - Timestamp: $timestamp"
    git stash save --include-untracked "$stash_name" >/dev/null 2>&1 || {
        log_error "Failed to stash changes."
        exit 1
    }
    echo "$stash_name"
}

# Function to backup local branches
backup_local_branches() {
    backup_file=".git/backup_branches.txt"
    log_info "Creating a backup of local branches in $backup_file..."
    git branch --list | grep -v "^\*" | tr -d ' ' >"$backup_file"
}

# Function to delete local branches
delete_local_branches() {
    primary_branch="$1"
    shift
    branches_to_delete="$*"
    for branch in $branches_to_delete; do
        log_info "Deleting local branch '$branch'..."
        git branch -D "$branch" >/dev/null 2>&1 || log_error "Failed to delete local branch '$branch'."
    done
}

# Function to fetch and pull updates
fetch_and_pull_updates() {
    primary_branch="$1"
    log_info "Fetching updates from the remote repository with tags..."
    git fetch --all --tags --prune >/dev/null 2>&1 || {
        log_error "Failed to fetch updates from the remote repository."
        exit 1
    }
    log_info "Pulling the latest changes for branch '$primary_branch' from the remote repository..."
    git pull origin "$primary_branch" --prune --rebase --tags >/dev/null 2>&1 || {
        log_error "Failed to pull the latest changes from the remote repository."
        exit 1
    }
}

# Function to reapply or drop stashed changes
reapply_or_drop_stash() {
    stash_name="$1"
    reapply_stash="$2"
    if [ -n "$(git stash list)" ]; then
        if [ "$reapply_stash" = "y" ]; then
            log_info "Reapplying the stashed changes named '$stash_name'..."
            git stash pop >/dev/null 2>&1 || {
                log_error "Failed to reapply the stashed changes."
                exit 1
            }
        else
            log_info "Dropping the stashed changes named '$stash_name'..."
            git stash drop >/dev/null 2>&1 || {
                log_error "Failed to drop the stashed changes."
                exit 1
            }
        fi
    fi
}

# Function to prompt the user for cleanup confirmation
warns_user() {
    echo "${BOLD}"
    echo " ☛ This script will tidy up your local Git repository by:"
    echo "   - Removing all local branches except the primary branch."
    echo "   - Stashing any uncommitted changes temporarily with a timestamp."
    echo "   - Fetching and pulling the latest updates from the remote repository."
    echo "${RESET}"

    log_prompt " > Do you want to continue with the cleanup process? (y/N)"
    continue_cleaning=$(prompt)
    if [ "$continue_cleaning" != "y" ]; then
        log_warn "Cleanup process aborted by the user. Exiting."
        exit 0
    fi
}

# Function to check for required dependencies
check_dependencies() {
    command -v git >/dev/null 2>&1 || {
        log_error "git command not found. Please install git before running this script."
        exit 1
    }
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log_error "Neither curl nor wget command found. Please install one of them before running this script."
        exit 1
    fi
}

# Function to check internet connection
check_internet_connection() {
    if command -v curl >/dev/null 2>&1; then
        curl -s --head $NET_TEST_URL >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --spider $NET_TEST_URL >/dev/null 2>&1
    else
        log_error "Neither curl nor wget could be executed."
        exit 1
    fi

    if [ $? -ne 0 ]; then
        log_error "No internet connection. Please check your internet connection and try again."
        exit 1
    fi
}

# Main function
main() {
    check_dependencies
    check_git_repository
    check_internet_connection
    warns_user

    current_branch=$(get_current_branch)
    log_prompt " > Is '$current_branch' your primary branch? (y/N)"
    is_primary_branch=$(prompt)
    primary_branch=""
    if [ "$is_primary_branch" != "y" ]; then
        log_prompt "    > Please enter the name of your primary branch:"
        primary_branch=$(prompt)
    else
        primary_branch=$current_branch
    fi

    delete_branches=""
    for branch in $(git branch --list | tr -d '* '); do
        if [ "$branch" != "$primary_branch" ]; then
            log_prompt "    > Are you sure you want to delete the branch '$branch'? (y/N)"
            confirm_delete=$(prompt)
            if [ "$confirm_delete" = "y" ]; then
                delete_branches="$delete_branches $branch"
            fi
        fi
    done

    log_prompt " > Do you want to reapply stashed changes after the cleanup process? (y/N)"
    reapply_stash=$(prompt)

    log_file=".git/cleanup_log.txt"
    echo "Cleanup process started at $(date)" >>"$log_file"
    log_info "Cleanup process initiated..."

    stash_name=""
    if [ "$(needs_stash)" = "yes" ]; then
        log_info "Uncommitted changes detected. Stashing changes temporarily..."
        stash_name=$(stash_changes "$primary_branch")
    else
        log_info "No uncommitted changes detected. No stashing required."
    fi

    backup_local_branches

    if [ "$primary_branch" != "$current_branch" ]; then
        log_info "Switching to the primary branch '$primary_branch'..."
        git checkout -B "$primary_branch" --force --quiet >/dev/null 2>&1 || {
            log_error "Failed to switch to the primary branch '$primary_branch'."
            exit 1
        }
    fi

    delete_local_branches "$primary_branch" "$delete_branches"

    fetch_and_pull_updates "$primary_branch"

    log_prompt " > Do you want to switch back to the previous branch '$current_branch'? (y/N)"
    switch_back=$(prompt)
    if [ "$switch_back" = "y" ]; then
        log_info "Switching back to the branch '$current_branch'..."
        git checkout -B "$current_branch" --force --quiet >/dev/null 2>&1 || {
            log_error "Failed to switch back to the branch '$current_branch'."
            exit 1
        }
    fi

    if [ -n "$stash_name" ]; then
        reapply_or_drop_stash "$stash_name" "$reapply_stash"
    fi

    log_success "Cleanup process completed successfully!"
    echo "Cleanup process finished at $(date)" >>"$log_file"
}

# Run the main function
main
