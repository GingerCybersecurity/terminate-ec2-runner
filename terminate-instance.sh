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

# ── Terminate the specified instance ─────────────────────────────────────────
log_info "Terminating EC2 instance ${INPUT_EC2_INSTANCE_ID}"
aws ec2 terminate-instances --instance-ids "$INPUT_EC2_INSTANCE_ID"

# Get final instance state
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INPUT_EC2_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text)

log_info "Instance state: ${INSTANCE_STATE}"
set_output "instance-state" "$INSTANCE_STATE"

# ── Optional: clean up stale instances by tag key/value ──────────────────────
if [[ -n "$INPUT_CLEANUP_STALE_TAG_KEY" || -n "$INPUT_CLEANUP_STALE_TAG_VALUE" ]]; then
    [[ -z "$INPUT_CLEANUP_STALE_TAG_KEY" ]] && log_error "cleanup-stale-tag-key is required when cleanup-stale-tag-value is set"
    [[ -z "$INPUT_CLEANUP_STALE_TAG_VALUE" ]] && log_error "cleanup-stale-tag-value is required when cleanup-stale-tag-key is set"

    STALE_MINUTES="${INPUT_CLEANUP_STALE_MINUTES:-60}"
    log_info "Cleanup: looking for instances with tag ${INPUT_CLEANUP_STALE_TAG_KEY}=${INPUT_CLEANUP_STALE_TAG_VALUE} older than ${STALE_MINUTES} minutes"

    CUTOFF_EPOCH=$(date -u -d "${STALE_MINUTES} minutes ago" '+%s')

    INSTANCES_JSON=$(aws ec2 describe-instances \
        --filters \
            "Name=tag:${INPUT_CLEANUP_STALE_TAG_KEY},Values=${INPUT_CLEANUP_STALE_TAG_VALUE}" \
            "Name=instance-state-name,Values=pending,running,stopped" \
        --query 'Reservations[].Instances[].[InstanceId, LaunchTime]' \
        --output json)

    TERMINATED_IDS=()

    while IFS= read -r entry; do
        INSTANCE_ID=$(echo "$entry" | jq -r '.[0]')
        LAUNCH_TIME=$(echo "$entry" | jq -r '.[1]')
        LAUNCH_EPOCH=$(date -d "$LAUNCH_TIME" '+%s')

        if [[ "$LAUNCH_EPOCH" -le "$CUTOFF_EPOCH" ]]; then
            log_info "Terminating stale instance ${INSTANCE_ID} (launched ${LAUNCH_TIME})"
            aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"
            TERMINATED_IDS+=("$INSTANCE_ID")
        else
            log_info "Skipping instance ${INSTANCE_ID} (launched ${LAUNCH_TIME}, not old enough)"
        fi
    done < <(echo "$INSTANCES_JSON" | jq -c '.[]')

    TERMINATED_COUNT="${#TERMINATED_IDS[@]}"
    log_info "Cleanup complete: terminated ${TERMINATED_COUNT} stale instance(s)"
    set_output "terminated-count" "$TERMINATED_COUNT"
    set_output "terminated-instance-ids" "$(IFS=','; echo "${TERMINATED_IDS[*]}")"
fi
