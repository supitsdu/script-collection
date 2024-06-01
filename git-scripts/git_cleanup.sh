#!/bin/bash

# Function to handle errors
function handle_error {
    echo "[ERROR] $1"
    echo "[ERROR] $1" >>.git/cleanup_log.txt
    exit 1
}

# Function to prompt user for input
function prompt {
    read -p "$1 " response
    response=${response:-'n'}
    echo "$response"
}

# Function to generate timestamp
function generate_timestamp {
    date +"%Y-%m-%d_%H-%M-%S"
}

# Ensure we are in a git repository
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || handle_error "Not a git repository. Exiting."

# Provide information about the cleanup process
echo
echo " ☛ This script will clean up your local Git repository by removing all"
echo "   local branches except the specified main/master branch."
echo "   It will also stash any uncommitted changes temporarily with a timestamp"
echo "   and fetch the latest updates from the remote repository."
echo

# Prompt user to confirm if they want to proceed
continue_cleaning=$(prompt " > Do you want to continue? (y/N)")
continue_cleaning=$(echo "$continue_cleaning" | tr '[:upper:]' '[:lower:]')
if [ "$continue_cleaning" != "y" ]; then
    echo "[WARNING] Cleanup aborted. Exiting."
    exit 0
fi

# Create a log file inside .git directory
log_file=".git/cleanup_log.txt"
echo "Cleanup started at $(date)" >"$log_file"

# Stash any uncommitted changes with timestamp
timestamp=$(generate_timestamp)
stash_name="Temporary stash before cleaning - $timestamp"
echo " • Stashing any uncommitted changes with timestamp '$timestamp'..."
git stash save --include-untracked "$stash_name" >/dev/null || handle_error "Failed to stash changes."

# Get the current branch
current_branch=$(git branch --show-current) || handle_error "Failed to get the current branch."
echo " • Current branch is '$current_branch'."

# Prompt user to confirm if the current branch is the main/master branch
is_main_branch=$(prompt " > Is '$current_branch' the main/master branch? (y/N)")
is_main_branch=$(echo "$is_main_branch" | tr '[:upper:]' '[:lower:]')
if [ "$is_main_branch" != "y" ]; then
    main_branch=$(prompt " > Enter the name of the main/master branch:")
else
    main_branch=$current_branch
fi

# Backup local branches to a file inside .git directory
backup_file=".git/backup_branches.txt"
echo " • Backing up local branches to $backup_file..."
git branch --list | grep -v "^\*" | tr -d ' ' >"$backup_file"

# Delete all local branches except the main/master branch
echo " • Deleting all local branches except the '$main_branch' branch..."
for branch in $(git branch --list | grep -v "^\*" | tr -d ' '); do
    if [ "$branch" != "$main_branch" ]; then
        confirm_delete=$(prompt "   > Are you sure you want to delete branch '$branch'? (y/N)")
        confirm_delete=$(echo "$confirm_delete" | tr '[:upper:]' '[:lower:]')
        if [ "$confirm_delete" == "y" ]; then
            echo " • Deleting local branch '$branch'"
            git branch -D "$branch" >/dev/null || handle_error "Failed to delete branch '$branch'."
            echo "[INFO] Deleted branch '$branch'" >>"$log_file"
        else
            echo "[INFO] Skipped deleting branch '$branch'" >>"$log_file"
        fi
    fi
done

# Drop the stash
echo " • Dropping the temporary stash..."
git stash drop >/dev/null || handle_error "Failed to drop the stash."

# Fetch updates from origin
echo " • Fetching updates from origin..."
git fetch origin >/dev/null || handle_error "Failed to fetch from origin."

# Pull the latest changes for the main/master branch
echo " • Pulling latest changes for branch '$main_branch' from origin..."
git pull origin "$main_branch" || handle_error "Failed to pull the latest changes."

# Optionally reapply the stashed changes
reapply_stash=$(prompt " > Do you want to reapply the stashed changes? (y/N)")
reapply_stash=$(echo "$reapply_stash" | tr '[:upper:]' '[:lower:]')
if [ "$reapply_stash" == "y" ]; then
    echo " • Reapplying the stashed changes..."
    git stash pop >/dev/null || handle_error "Failed to reapply the stashed changes."
fi

echo " ✔ Done"
echo "Cleanup finished at $(date)" >>"$log_file"
