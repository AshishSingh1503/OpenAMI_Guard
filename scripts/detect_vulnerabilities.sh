#!/usr/bin/env bash
set -euo pipefail

SEVERITY_THRESHOLD="${SEVERITY_THRESHOLD:-HIGH}"
LOOKBACK_DAYS="${LOOKBACK_DAYS:-7}"
AMI_PARAMETER_NAME="${AMI_PARAMETER_NAME:-/openami-guard/current_ami_id}"
REGION="${AWS_REGION:-ap-south-1}"
SOURCE_AMI_NAME_PATTERN="${SOURCE_AMI_NAME_PATTERN:-ubuntu/images/hvm-ssd/ubuntu-*-24.04-amd64-server-*}"
SOURCE_AMI_OWNER="${SOURCE_AMI_OWNER:-099720109477}"
SOURCE_AMI_VIRTUALIZATION_TYPE="${SOURCE_AMI_VIRTUALIZATION_TYPE:-hvm}"
SOURCE_AMI_ROOT_DEVICE_TYPE="${SOURCE_AMI_ROOT_DEVICE_TYPE:-ebs}"

threshold_rank() {
  case "$1" in
    CRITICAL) echo 4 ;;
    HIGH) echo 3 ;;
    MEDIUM) echo 2 ;;
    LOW) echo 1 ;;
    *) echo 0 ;;
  esac
}

severity_rank="$(threshold_rank "$SEVERITY_THRESHOLD")"
cutoff="$(date -u -d "-${LOOKBACK_DAYS} days" +"%Y-%m-%dT%H:%M:%SZ")"

echo "[INFO] Checking SSM parameter ${AMI_PARAMETER_NAME}"
current_ami="$(aws ssm get-parameter \
  --name "$AMI_PARAMETER_NAME" \
  --region "$REGION" \
  --query 'Parameter.Value' \
  --output text 2>/dev/null || true)"

if [[ -z "$current_ami" || "$current_ami" == "None" ]]; then
  echo "[WARN] No current AMI published yet. Rebuild required."
  echo "rebuild_required=true" >> "$GITHUB_OUTPUT"
  echo "reason=bootstrap-no-current-ami" >> "$GITHUB_OUTPUT"
  echo "explain_reason=No current AMI was published yet" >> "$GITHUB_OUTPUT"
  echo "affected_packages=[]" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "[INFO] Current AMI: ${current_ami}"

base_ami="$(aws ec2 describe-images \
  --owners "$SOURCE_AMI_OWNER" \
  --region "$REGION" \
  --filters \
    "Name=name,Values=${SOURCE_AMI_NAME_PATTERN}" \
    "Name=virtualization-type,Values=${SOURCE_AMI_VIRTUALIZATION_TYPE}" \
    "Name=root-device-type,Values=${SOURCE_AMI_ROOT_DEVICE_TYPE}" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
  --output text)"

rebuild_required=false
reason="none"
explain_reason="No infra change required"
affected_packages_json="[]"

if [[ "$base_ami" != "$current_ami" ]]; then
  echo "[INFO] New upstream Ubuntu AMI detected: ${base_ami}"
  rebuild_required=true
  reason="new-base-ami"
  explain_reason="New upstream base AMI detected"
fi

echo "[INFO] Querying Inspector findings since ${cutoff}"
findings_json="$(aws inspector2 list-findings \
  --region "$REGION" \
  --filter-criteria "{
    \"findingStatus\": [{\"comparison\": \"EQUALS\", \"value\": \"ACTIVE\"}],
    \"resourceType\": [{\"comparison\": \"EQUALS\", \"value\": \"AWS_EC2_INSTANCE\"}]
  }" \
  --max-results 100 2>/dev/null || echo '{"findings":[]}' )"

matching_count="$(
  printf '%s' "$findings_json" | jq --arg ami "$current_ami" --arg cutoff "$cutoff" --argjson threshold "$severity_rank" '
    [.findings[]
      | select(.resources[]?.details.awsEc2Instance?.imageId == $ami)
      | select((.firstObservedAt // "") >= $cutoff)
      | select(
          (if .severity == "CRITICAL" then 4
           elif .severity == "HIGH" then 3
           elif .severity == "MEDIUM" then 2
           elif .severity == "LOW" then 1
           else 0 end) >= $threshold
        )
    ] | length
  '
)"

affected_packages_json="$(
  printf '%s' "$findings_json" | jq --arg ami "$current_ami" --arg cutoff "$cutoff" --argjson threshold "$severity_rank" '
    [
      .findings[]
      | select(.resources[]?.details.awsEc2Instance?.imageId == $ami)
      | select((.firstObservedAt // "") >= $cutoff)
      | select(
          (if .severity == "CRITICAL" then 4
           elif .severity == "HIGH" then 3
           elif .severity == "MEDIUM" then 2
           elif .severity == "LOW" then 1
           else 0 end) >= $threshold
        )
      | .packageVulnerabilityDetails.vulnerablePackages[]?.name
    ] | unique
  '
)"

echo "[INFO] Matching findings at or above ${SEVERITY_THRESHOLD}: ${matching_count}"

if [[ "${matching_count}" != "0" ]]; then
  rebuild_required=true
  reason="inspector-findings"
  if printf '%s' "$findings_json" | jq -e --arg ami "$current_ami" --arg cutoff "$cutoff" '
    any(
      .findings[];
      any(.resources[]?; .details.awsEc2Instance?.imageId == $ami)
      and (.firstObservedAt // "") >= $cutoff
      and .severity == "CRITICAL"
    )
  ' >/dev/null; then
    explain_reason="CRITICAL CVE detected"
  else
    explain_reason="${SEVERITY_THRESHOLD} severity vulnerability drift detected"
  fi
fi

echo "rebuild_required=${rebuild_required}" >> "$GITHUB_OUTPUT"
echo "reason=${reason}" >> "$GITHUB_OUTPUT"
echo "explain_reason=${explain_reason}" >> "$GITHUB_OUTPUT"
echo "affected_packages=${affected_packages_json}" >> "$GITHUB_OUTPUT"
