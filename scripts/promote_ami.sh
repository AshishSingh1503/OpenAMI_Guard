#!/usr/bin/env bash
set -euo pipefail

AMI_ID="${1:?usage: promote_ami.sh <ami-id>}"
REGION="${AWS_REGION:-ap-south-1}"
AMI_PARAMETER_NAME="${AMI_PARAMETER_NAME:-/golden/ubuntu24/ami_id}"
LAST_KNOWN_GOOD_PARAMETER_NAME="${LAST_KNOWN_GOOD_PARAMETER_NAME:-/golden/ubuntu24/last_known_good_ami_id}"
INSTANCE_REFRESH_ID="${INSTANCE_REFRESH_ID:?INSTANCE_REFRESH_ID is required}"
AUTO_SCALING_GROUP_NAME="${AUTO_SCALING_GROUP_NAME:?AUTO_SCALING_GROUP_NAME is required}"

while true; do
  refresh_status="$(aws autoscaling describe-instance-refreshes \
    --region "$REGION" \
    --auto-scaling-group-name "$AUTO_SCALING_GROUP_NAME" \
    --instance-refresh-ids "$INSTANCE_REFRESH_ID" \
    --query 'InstanceRefreshes[0].Status' \
    --output text)"

  echo "[INFO] Current refresh status: ${refresh_status}"

  if [[ "$refresh_status" == "Successful" ]]; then
    break
  fi

  if [[ "$refresh_status" == "Failed" || "$refresh_status" == "Cancelled" ]]; then
    echo "[ERROR] Instance refresh ended in status ${refresh_status}"
    exit 1
  fi

  sleep 30
done

current_live_ami="$(aws ssm get-parameter \
  --region "$REGION" \
  --name "$AMI_PARAMETER_NAME" \
  --query 'Parameter.Value' \
  --output text 2>/dev/null || true)"

if [[ -n "$current_live_ami" && "$current_live_ami" != "None" ]]; then
  aws ssm put-parameter \
    --region "$REGION" \
    --name "$LAST_KNOWN_GOOD_PARAMETER_NAME" \
    --value "$current_live_ami" \
    --type String \
    --overwrite >/dev/null
fi

aws ssm put-parameter \
  --region "$REGION" \
  --name "$AMI_PARAMETER_NAME" \
  --value "$AMI_ID" \
  --type String \
  --overwrite >/dev/null
