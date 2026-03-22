#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-ap-south-1}"
AUTO_SCALING_GROUP_NAME="${AUTO_SCALING_GROUP_NAME:?AUTO_SCALING_GROUP_NAME is required}"
LAUNCH_TEMPLATE_ID="${LAUNCH_TEMPLATE_ID:?LAUNCH_TEMPLATE_ID is required}"
PREVIOUS_VERSION="${PREVIOUS_VERSION:?PREVIOUS_VERSION is required}"
INSTANCE_REFRESH_ID="${INSTANCE_REFRESH_ID:?INSTANCE_REFRESH_ID is required}"
LAST_KNOWN_GOOD_PARAMETER_NAME="${LAST_KNOWN_GOOD_PARAMETER_NAME:-/golden/ubuntu24/last_known_good_ami_id}"

echo "[INFO] Cancelling canary rollout ${INSTANCE_REFRESH_ID}"
aws autoscaling cancel-instance-refresh \
  --region "$REGION" \
  --auto-scaling-group-name "$AUTO_SCALING_GROUP_NAME"

echo "[INFO] Restoring launch template version ${PREVIOUS_VERSION}"
aws autoscaling update-auto-scaling-group \
  --region "$REGION" \
  --auto-scaling-group-name "$AUTO_SCALING_GROUP_NAME" \
  --launch-template "LaunchTemplateId=${LAUNCH_TEMPLATE_ID},Version=${PREVIOUS_VERSION}"

last_known_good_ami="$(aws ssm get-parameter \
  --region "$REGION" \
  --name "$LAST_KNOWN_GOOD_PARAMETER_NAME" \
  --query 'Parameter.Value' \
  --output text)"

echo "[INFO] Restarting rollout on last known good AMI ${last_known_good_ami}"
aws autoscaling start-instance-refresh \
  --region "$REGION" \
  --auto-scaling-group-name "$AUTO_SCALING_GROUP_NAME" \
  --preferences 'MinHealthyPercentage=100,InstanceWarmup=180' >/dev/null
