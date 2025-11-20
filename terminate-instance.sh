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

# Check required inputs
[[ -z "$INPUT_EC2_INSTANCE_ID" ]] && log_error "ec2-instance-id is required"

# Stop the instance
log_info "Terminating EC2 instance ${INPUT_EC2_INSTANCE_ID}"
aws ec2 terminate-instances --instance-ids "$INPUT_EC2_INSTANCE_ID"

# Get final instance state
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INPUT_EC2_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text)

log_info "Instance state: ${INSTANCE_STATE}"
set_output "instance-state" "$INSTANCE_STATE"
