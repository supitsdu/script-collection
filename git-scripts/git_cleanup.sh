#!/bin/bash

# ANSI color codes
RESET='\033[0m'
BOLD='\033[1m'
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
BLUE='\033[34m'

# Function to handle errors
function handle_error {
    echo -e "${RED}[ERROR] $1${RESET}"
    echo "[ERROR] $1" >>.git/cleanup_log.txt
    exit 1
}

# Function to log info messages
function log_info {
    echo -e "${BLUE}[INFO] $1${RESET}"
    echo "[INFO] $1" >>.git/cleanup_log.txt
}

# Function to log warnings
function log_warn {
    echo -e "${YELLOW}[WARNING] $1${RESET}"
    echo "[WARNING] $1" >>.git/cleanup_log.txt
}

# Function to prompt user for input
function prompt {
    read -r -p "$1 " response
    response=${response:-'n'}
    echo "$response" | tr '[:upper:]' '[:lower:]'
}

# Function to generate timestamp
function generate_timestamp {
    date +"%Y-%m-%d_%H-%M-%S"
}

# Function to ensure we are in a git repository
function check_git_repository {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || handle_error "Not a git repository. Exiting."
}

# Function to get the current branch
function get_current_branch {
    git branch --show-current || handle_error "Failed to retrieve the current branch."
}

# Function to check if there are changes to stash
function needs_stash {
    if ! git diff-index --quiet HEAD --; then
        echo "yes"
    else
        echo "no"
    fi
}

# Function to stash changes
function stash_changes {
    local timestamp=$(generate_timestamp)
    local stash_name="Backup of uncommitted changes - Branch: $1 - Timestamp: $timestamp"
    git stash save --include-untracked "$stash_name" >/dev/null 2>&1 || handle_error "Failed to stash changes."
    echo "$stash_name"
}

# Function to backup local branches
function backup_local_branches {
    local backup_file=".git/backup_branches.txt"
    log_info "Creating a backup of local branches in $backup_file..."
    git branch --list | grep -v "^\*" | tr -d ' ' >"$backup_file"
}

# Function to delete local branches
function delete_local_branches {
    local main_branch=$1
    shift
    local branches_to_delete=("$@")
    for branch in "${branches_to_delete[@]}"; do
        log_info "Deleting local branch '$branch'..."
        git branch -D "$branch" >/dev/null 2>&1 || handle_error "Failed to delete local branch '$branch'."
    done
}

# Function to fetch and pull updates
function fetch_and_pull_updates {
    local main_branch=$1
    log_info "Fetching updates from the remote repository with tags..."
    git fetch origin --tags >/dev/null 2>&1 || handle_error "Failed to fetch updates from the remote repository."
    log_info "Pulling the latest changes for branch '$main_branch' from the remote repository..."
    git pull origin "$main_branch" --prune --rebase --tags >/dev/null 2>&1 || handle_error "Failed to pull the latest changes from the remote repository."
}

# Function to reapply or drop stashed changes
function reapply_or_drop_stash {
    local stash_name=$1
    local reapply_stash=$2
    if [ -n "$(git stash list)" ]; then
        if [ "$reapply_stash" == "y" ]; then
            log_info "Reapplying the stashed changes named '$stash_name'..."
            git stash pop >/dev/null 2>&1 || handle_error "Failed to reapply the stashed changes."
        else
            log_info "Dropping the stashed changes named '$stash_name'..."
            git stash drop >/dev/null 2>&1 || handle_error "Failed to drop the stashed changes."
        fi
    fi
}

# Main function
function main {
    check_git_repository

    # Provide information about the cleanup process
    echo -e "${BOLD}"
    echo " ☛ This script will tidy up your local Git repository by:"
    echo "   - Removing all local branches except the main/master branch."
    echo "   - Stashing any uncommitted changes temporarily with a timestamp."
    echo "   - Fetching and pulling the latest updates from the remote repository."
    echo -e "${RESET}"

    # Prompt user to confirm if they want to proceed
    local continue_cleaning=$(prompt " > Do you want to continue with the cleanup process? (y/N)")
    if [ "$continue_cleaning" != "y" ]; then
        log_warn "Cleanup process aborted by the user. Exiting."
        exit 0
    fi

    # Get the current branch
    local current_branch=$(get_current_branch)

    # Prompt user to confirm if the current branch is the primary branch
    local is_main_branch=$(prompt " > Is '$current_branch' your primary branch? (y/N)")
    if [ "$is_main_branch" != "y" ]; then
        main_branch=$(prompt " > Please enter the name of your primary branch:")
    else
        main_branch=$current_branch
    fi

    # Prompt user to confirm deletion of each branch
    local delete_branches=()
    for branch in $(git branch --list | grep -v "^\*" | tr -d ' '); do
        if [ "$branch" != "$main_branch" ]; then
            local confirm_delete=$(prompt "   > Are you sure you want to delete the branch '$branch'? (y/N)")
            if [ "$confirm_delete" == "y" ]; then
                delete_branches+=("$branch")
            fi
        fi
    done

    local reapply_stash=$(prompt " > Do you want to reapply stashed changes after the cleanup process? (y/N)")

    # Create a log file inside .git directory
    local log_file=".git/cleanup_log.txt"
    echo "Cleanup process started at $(date)" >>"$log_file"
    log_info "Cleanup process initiated..."

    # Initialize stash_name variable
    local stash_name=""

    # Check if there are changes to stash
    if [ "$(needs_stash)" == "yes" ]; then
        log_info "Uncommitted changes detected. Stashing changes temporarily..."
        stash_name=$(stash_changes "$main_branch")
    else
        log_info "No uncommitted changes detected. No stashing required."
    fi

    # Backup local branches
    backup_local_branches

    # Delete local branches
    delete_local_branches "$main_branch" "${delete_branches[@]}"

    # Fetch and pull updates
    fetch_and_pull_updates "$main_branch"

    # Reapply or drop stashed changes
    if [ -n "$stash_name" ]; then
        reapply_or_drop_stash "$stash_name" "$reapply_stash"
    fi

    echo -e "${GREEN}[SUCCESS] Cleanup process completed successfully!${RESET}"
    echo "Cleanup process finished at $(date)" >>"$log_file"
}

# Run the main function
main
