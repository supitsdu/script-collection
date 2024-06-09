#!/bin/sh
# Any copyright is dedicated to the Public Domain.
# https://creativecommons.org/publicdomain/zero/1.0/

# ANSI color codes
RESET='\e[0m'
BOLD='\e[1m'
GREEN='\e[32m'
RED='\e[31m'
YELLOW='\e[33m'
BLUE='\e[34m'

# Function to handle errors
handle_error() {
    echo "${RED}[ERROR] $1$RESET"
    echo "[ERROR] $1" >>.git/cleanup_log.txt
    exit 1
}

# Function to log info messages
log_info() {
    echo "${BLUE}[INFO] $1$RESET"
    echo "[INFO] $1" >>.git/cleanup_log.txt
}

# Function to log warnings
log_warn() {
    echo "${YELLOW}[WARNING] ${1}${RESET}"
    echo "[WARNING] $1" >>.git/cleanup_log.txt
}

# Function to log info messages
log_success() {
    echo "${GREEN}[SUCCESS] $1$RESET"
    echo "[SUCCESS] $1" >>.git/cleanup_log.txt
}

log_prompt() {
    printf "$BOLD%s$RESET " "$1"
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
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || handle_error "Not a git repository. Exiting."
}

# Function to get the current branch
get_current_branch() {
    git branch --show-current || handle_error "Failed to retrieve the current branch."
}

# Function to check if there are changes to stash
needs_stash() {
    if ! git diff-index --quiet HEAD --; then
        echo "yes"
    else
        echo "no"
    fi
}

# Function to stash changes
stash_changes() {
    timestamp=$(generate_timestamp)
    stash_name="Backup of uncommitted changes - Branch: $1 - Timestamp: $timestamp"
    git stash save --include-untracked "$stash_name" >/dev/null 2>&1 || handle_error "Failed to stash changes."
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
    main_branch=$1
    shift
    branches_to_delete="$*"
    for branch in $branches_to_delete; do
        log_info "Deleting local branch '$branch'..."
        git branch -D "$branch" >/dev/null 2>&1 || handle_error "Failed to delete local branch '$branch'."
    done
}

# Function to fetch and pull updates
fetch_and_pull_updates() {
    main_branch=$1
    log_info "Fetching updates from the remote repository with tags..."
    git fetch origin --tags >/dev/null 2>&1 || handle_error "Failed to fetch updates from the remote repository."
    log_info "Pulling the latest changes for branch '$main_branch' from the remote repository..."
    git pull origin "$main_branch" --prune --rebase --tags >/dev/null 2>&1 || handle_error "Failed to pull the latest changes from the remote repository."
}

# Function to reapply or drop stashed changes
reapply_or_drop_stash() {
    stash_name=$1
    reapply_stash=$2
    if [ -n "$(git stash list)" ]; then
        if [ "$reapply_stash" = "y" ]; then
            log_info "Reapplying the stashed changes named '$stash_name'..."
            git stash pop >/dev/null 2>&1 || handle_error "Failed to reapply the stashed changes."
        else
            log_info "Dropping the stashed changes named '$stash_name'..."
            git stash drop >/dev/null 2>&1 || handle_error "Failed to drop the stashed changes."
        fi
    fi
}

# Main function
main() {
    check_git_repository

    # Provide information about the cleanup process
    echo "$BOLD"
    echo " ☛ This script will tidy up your local Git repository by:"
    echo "   - Removing all local branches except the main/master branch."
    echo "   - Stashing any uncommitted changes temporarily with a timestamp."
    echo "   - Fetching and pulling the latest updates from the remote repository."
    echo "$RESET"

    # Prompt user to confirm if they want to proceed
    log_prompt " > Do you want to continue with the cleanup process? (y/N)"
    continue_cleaning=$(prompt)
    if [ "$continue_cleaning" != "y" ]; then
        log_warn "Cleanup process aborted by the user. Exiting."
        exit 0
    fi

    # Get the current branch
    current_branch=$(get_current_branch)

    # Prompt user to confirm if the current branch is the primary branch
    log_prompt " > Is '$current_branch' your primary branch? (y/N)"
    is_main_branch=$(prompt)
    if [ "$is_main_branch" != "y" ]; then
        log_prompt " > Please enter the name of your primary branch:"
        main_branch=$(prompt)
    else
        main_branch=$current_branch
    fi

    # Prompt user to confirm deletion of each branch
    delete_branches=""
    for branch in $(git branch --list | grep -v "^\*" | tr -d ' '); do
        if [ "$branch" != "$main_branch" ]; then
            log_prompt "   > Are you sure you want to delete the branch '$branch'? (y/N)"
            confirm_delete=$(prompt)
            if [ "$confirm_delete" = "y" ]; then
                delete_branches="$delete_branches $branch"
            fi
        fi
    done

    log_prompt " > Do you want to reapply stashed changes after the cleanup process? (y/N)"
    reapply_stash=$(prompt)

    # Create a log file inside .git directory
    log_file=".git/cleanup_log.txt"
    echo "Cleanup process started at $(date)" >>"$log_file"
    log_info "Cleanup process initiated..."

    # Initialize stash_name variable
    stash_name=""

    # Check if there are changes to stash
    if [ "$(needs_stash)" = "yes" ]; then
        log_info "Uncommitted changes detected. Stashing changes temporarily..."
        stash_name=$(stash_changes "$main_branch")
    else
        log_info "No uncommitted changes detected. No stashing required."
    fi

    # Backup local branches
    backup_local_branches

    # Delete local branches
    delete_local_branches "$main_branch" "$delete_branches"

    # Fetch and pull updates
    fetch_and_pull_updates "$main_branch"

    # Reapply or drop stashed changes
    if [ -n "$stash_name" ]; then
        reapply_or_drop_stash "$stash_name" "$reapply_stash"
    fi

    log_success "Cleanup process completed successfully!"
    echo "Cleanup process finished at $(date)" >>"$log_file"
}

# Run the main function
main
