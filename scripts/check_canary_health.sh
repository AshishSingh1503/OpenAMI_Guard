#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
AUTO_SCALING_GROUP_NAME="${AUTO_SCALING_GROUP_NAME:?AUTO_SCALING_GROUP_NAME is required}"
INSTANCE_REFRESH_ID="${INSTANCE_REFRESH_ID:?INSTANCE_REFRESH_ID is required}"
HEALTH_ALARM_NAME="${HEALTH_ALARM_NAME:?HEALTH_ALARM_NAME is required}"

refresh_status="$(aws autoscaling describe-instance-refreshes \
  --region "$REGION" \
  --auto-scaling-group-name "$AUTO_SCALING_GROUP_NAME" \
  --instance-refresh-ids "$INSTANCE_REFRESH_ID" \
  --query 'InstanceRefreshes[0].Status' \
  --output text)"

alarm_state="$(aws cloudwatch describe-alarms \
  --region "$REGION" \
  --alarm-names "$HEALTH_ALARM_NAME" \
  --query 'MetricAlarms[0].StateValue' \
  --output text)"

echo "[INFO] Canary refresh status: ${refresh_status}"
echo "[INFO] Health alarm state: ${alarm_state}"

if [[ "$alarm_state" == "ALARM" || "$refresh_status" == "Failed" || "$refresh_status" == "Cancelled" ]]; then
  echo "rollback_required=true" >> "$GITHUB_OUTPUT"
else
  echo "rollback_required=false" >> "$GITHUB_OUTPUT"
fi
