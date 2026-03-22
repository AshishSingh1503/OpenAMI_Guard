#!/usr/bin/env bash
set -euo pipefail

AMI_ID="${1:?usage: canary_rollout.sh <ami-id>}"
REGION="${AWS_REGION:-ap-south-1}"
LAUNCH_TEMPLATE_ID="${LAUNCH_TEMPLATE_ID:?LAUNCH_TEMPLATE_ID is required}"
AUTO_SCALING_GROUP_NAME="${AUTO_SCALING_GROUP_NAME:?AUTO_SCALING_GROUP_NAME is required}"
CANARY_PERCENTAGE="${CANARY_PERCENTAGE:-10}"
INSTANCE_WARMUP="${INSTANCE_WARMUP:-180}"
BAKE_TIME_SECONDS="${BAKE_TIME_SECONDS:-600}"

echo "[INFO] Capturing current launch template version"
previous_version="$(aws autoscaling describe-auto-scaling-groups \
  --region "$REGION" \
  --auto-scaling-group-names "$AUTO_SCALING_GROUP_NAME" \
  --query 'AutoScalingGroups[0].LaunchTemplate.Version' \
  --output text)"

echo "previous_version=${previous_version}" >> "$GITHUB_OUTPUT"

echo "[INFO] Creating launch template version for ${AMI_ID}"
new_version="$(aws ec2 create-launch-template-version \
  --region "$REGION" \
  --launch-template-id "$LAUNCH_TEMPLATE_ID" \
  --source-version '$Latest' \
  --launch-template-data "{\"ImageId\":\"${AMI_ID}\"}" \
  --query 'LaunchTemplateVersion.VersionNumber' \
  --output text)"

echo "new_version=${new_version}" >> "$GITHUB_OUTPUT"

aws autoscaling update-auto-scaling-group \
  --region "$REGION" \
  --auto-scaling-group-name "$AUTO_SCALING_GROUP_NAME" \
  --launch-template "LaunchTemplateId=${LAUNCH_TEMPLATE_ID},Version=${new_version}"

echo "[INFO] Starting canary instance refresh"
refresh_id="$(aws autoscaling start-instance-refresh \
  --region "$REGION" \
  --auto-scaling-group-name "$AUTO_SCALING_GROUP_NAME" \
  --preferences "MinHealthyPercentage=$((100 - CANARY_PERCENTAGE)),InstanceWarmup=${INSTANCE_WARMUP},CheckpointPercentages=[${CANARY_PERCENTAGE}],CheckpointDelay=${BAKE_TIME_SECONDS}" \
  --query 'InstanceRefreshId' \
  --output text)"

echo "instance_refresh_id=${refresh_id}" >> "$GITHUB_OUTPUT"
