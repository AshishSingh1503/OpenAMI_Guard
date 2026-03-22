#!/usr/bin/env bash
set -euo pipefail

AMI_ID="${1:?usage: test_ami.sh <ami-id>}"
REGION="${AWS_REGION:-ap-south-1}"
INSTANCE_TYPE="${TEST_INSTANCE_TYPE:-t3.micro}"
SUBNET_ID="${TEST_SUBNET_ID:?TEST_SUBNET_ID is required}"
SECURITY_GROUP_ID="${TEST_SECURITY_GROUP_ID:?TEST_SECURITY_GROUP_ID is required}"
INSTANCE_PROFILE="${TEST_INSTANCE_PROFILE:?TEST_INSTANCE_PROFILE is required}"
VALIDATION_TIMEOUT_SECONDS="${VALIDATION_TIMEOUT_SECONDS:-900}"

echo "[INFO] Launching validation instance for ${AMI_ID}"
instance_id="$(aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SECURITY_GROUP_ID" \
  --iam-instance-profile Name="$INSTANCE_PROFILE" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=golden-ami-validation},{Key=Role,Value=validation}]' \
  --query 'Instances[0].InstanceId' \
  --output text)"

cleanup() {
  echo "[INFO] Terminating validation instance ${instance_id}"
  aws ec2 terminate-instances --region "$REGION" --instance-ids "$instance_id" >/dev/null || true
}
trap cleanup EXIT

aws ec2 wait instance-status-ok --region "$REGION" --instance-ids "$instance_id"

deadline="$(( $(date +%s) + VALIDATION_TIMEOUT_SECONDS ))"
while true; do
  ping_status="$(aws ssm describe-instance-information \
    --region "$REGION" \
    --filters "Key=InstanceIds,Values=${instance_id}" \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text 2>/dev/null || true)"
  if [[ "$ping_status" == "Online" ]]; then
    break
  fi
  if (( $(date +%s) > deadline )); then
    echo "[ERROR] SSM agent did not come online in time"
    exit 1
  fi
  sleep 15
done

echo "[INFO] Running smoke tests over SSM"
command_id="$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$instance_id" \
  --document-name 'AWS-RunShellScript' \
  --parameters 'commands=["cd /tmp","cat <<'\''EOF'\'' > /tmp/ami-validation.sh\n#!/usr/bin/env bash\nset -euo pipefail\n\nassert_service_active() {\n  local service=\"$1\"\n  local state\n  state=\"$(systemctl is-active \"$service\")\"\n  echo \"[INFO] service ${service}: ${state}\"\n  [[ \"$state\" == \"active\" ]]\n}\n\nassert_port_not_listening() {\n  local port=\"$1\"\n  if ss -lnt | awk '\''NR > 1 {print $4}'\'' | grep -Eq \"(^|[:.])${port}$\"; then\n    echo \"[ERROR] port ${port} is unexpectedly listening\"\n    exit 1\n  fi\n  echo \"[INFO] port ${port} is closed as expected\"\n}\n\nassert_binary_present() {\n  local binary=\"$1\"\n  command -v \"$binary\" >/dev/null\n  echo \"[INFO] binary ${binary} present\"\n}\n\nrun_test() {\n  local name=\"$1\"\n  shift\n  echo \"[TEST] ${name}\"\n  \"$@\"\n}\n\nrun_test \"ssm agent service\" assert_service_active amazon-ssm-agent\nrun_test \"ssh service\" assert_service_active ssh\nrun_test \"deploy user exists\" id deploy\nrun_test \"motd exists\" test -f /etc/motd\nrun_test \"ssm agent binary\" assert_binary_present amazon-ssm-agent\nrun_test \"cloudwatch agent binary\" assert_binary_present amazon-cloudwatch-agent\nrun_test \"cloudwatch agent package\" dpkg -s amazon-cloudwatch-agent\nrun_test \"root login disabled\" bash -lc \"sshd -T | grep -E '\''^permitrootlogin no$'\''\"\nrun_test \"password auth disabled\" bash -lc \"sshd -T | grep -E '\''^passwordauthentication no$'\''\"\nrun_test \"port 23 closed\" assert_port_not_listening 23\nrun_test \"port 80 closed\" assert_port_not_listening 80\nrun_test \"port 443 closed\" assert_port_not_listening 443\n\necho \"[INFO] automated AMI validation suite passed\"\nEOF","chmod +x /tmp/ami-validation.sh","sudo /tmp/ami-validation.sh"]' \
  --query 'Command.CommandId' \
  --output text)"

aws ssm wait command-executed \
  --region "$REGION" \
  --command-id "$command_id" \
  --instance-id "$instance_id"

status="$(aws ssm get-command-invocation \
  --region "$REGION" \
  --command-id "$command_id" \
  --instance-id "$instance_id" \
  --query 'Status' \
  --output text)"

echo "[INFO] Validation command status: ${status}"
[[ "$status" == "Success" ]]
