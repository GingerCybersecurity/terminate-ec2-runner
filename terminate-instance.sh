#!/bin/bash

# Function to set GitHub Actions output
set_output() {
    echo "$1=$2" >> "$GITHUB_OUTPUT"
}

# Function to log info
log_info() {
    echo "::info::$1" >&2
}

# Function to log error and exit
log_error() {
    echo "::error::$1" >&2
    exit 1
}

get_runner() {
    local label="$1"
    log_info "Trying to get runner with label ${label}"
    local owner_repo="${GITHUB_REPOSITORY}"  # Format: owner/repo

    # Get all runners at once using GitHub API
    response=$(curl -s -H "Accept: application/vnd.github.v3+json" \
                   -H "Authorization: Bearer $INPUT_GITHUB_TOKEN" \
                   "https://api.github.com/repos/${owner_repo}/actions/runners?per_page=100")

    # Check if the response is empty or has an error
    if [ "$(echo "$response" | jq -r 'length // 0')" -eq 0 ]; then
        log_info "No runners found in repository"
        return 1
    fi

    # Find runner with matching label
    runner=$(echo "$response" | jq -r --arg label "$label" '
        .runners[] |
        select(.labels[] | select(.name == $label)) |
        @json
    ')

    # If runner is found, output it and return success
    if [ ! -z "$runner" ]; then
        echo "$runner"
        return 0
    fi

    # If no runner found with matching label
    log_info "No runner found with label ${label}"
    return 1
}

remove_runner() {
    local label="$1"
    local token="$2"

    log_info "Trying to remove runner with label ${label}"

    # Get runner first using the get_runner function
    runner=$(get_runner "$label")
    if [ -z "$runner" ]; then
        log_info "Runner does not exist anymore - skipping removal."
        return 0
    fi

    # Extract runner ID from the JSON response
    runner_id=$(echo "$runner" | jq -r '.id')

    # Delete the runner using GitHub API
    response=$(curl -s -X DELETE \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Authorization: Bearer $token" \
       "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/actions/runners/$runner_id")

    # Check if the deletion was successful (empty response means success)
    if [ -z "$response" ]; then
        return 0
    else
        log_error "An error occurred while removing the runner from Github."
        log_error "$response"
        return 1
    fi
}

# Check required inputs
[[ -z "$INPUT_GITHUB_TOKEN" ]] && log_error "github-token is required"
[[ -z "$INPUT_RUNNER_LABEL" ]] && log_error "runner-label is required"
[[ -z "$INPUT_EC2_INSTANCE_ID" ]] && log_error "ec2-instance-id is required"

# Stop the instance
log_info "Terminating EC2 instance ${INPUT_EC2_INSTANCE_ID}"
aws ec2 terminate-instances --instance-ids "$INPUT_EC2_INSTANCE_ID"

 # Clean up the runner
remove_runner $INPUT_RUNNER_LABEL

# Get final instance state
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INPUT_EC2_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text)

log_info "Instance state: ${INSTANCE_STATE}"
set_output "instance-state" "$INSTANCE_STATE"
