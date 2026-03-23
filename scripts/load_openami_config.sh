#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-openami.yaml}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[WARN] OpenAMI config ${CONFIG_FILE} not found, keeping existing environment defaults"
  exit 0
fi

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

unquote() {
  local value
  value="$(trim "$1")"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "$value"
}

section=""
system_name=""
base_image_type=""
base_image_version=""
severity_threshold=""
canary_percentage=""
bake_time=""
slack_webhook=""

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$(trim "$line")" ]] && continue
  [[ "$(trim "$line")" == \#* ]] && continue

  if [[ "$line" =~ ^([a-z_]+):[[:space:]]*$ ]]; then
    section="${BASH_REMATCH[1]}"
    continue
  fi

  if [[ "$line" =~ ^([a-z_]+):[[:space:]]*(.+)$ ]]; then
    key="${BASH_REMATCH[1]}"
    value="$(unquote "${BASH_REMATCH[2]}")"
    if [[ -z "$section" ]]; then
      case "$key" in
        system) system_name="$value" ;;
      esac
    fi
    continue
  fi

  if [[ "$line" =~ ^[[:space:]]+([a-z_]+):[[:space:]]*(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    value="$(unquote "${BASH_REMATCH[2]}")"
    case "${section}.${key}" in
      base_image.type) base_image_type="$value" ;;
      base_image.version) base_image_version="$value" ;;
      security.severity_threshold) severity_threshold="$value" ;;
      rollout.canary_percentage) canary_percentage="$value" ;;
      rollout.bake_time) bake_time="$value" ;;
      notifications.slack_webhook) slack_webhook="$value" ;;
    esac
  fi
done < "$CONFIG_FILE"

system_name="${system_name:-${SYSTEM_NAME:-OpenAMI Guard}}"
base_image_type="${base_image_type:-ubuntu}"
base_image_version="${base_image_version:-24.04}"
severity_threshold="${severity_threshold:-${SEVERITY_THRESHOLD:-HIGH}}"
canary_percentage="${canary_percentage:-${CANARY_PERCENTAGE:-10}}"
bake_time="${bake_time:-${BAKE_TIME_SECONDS:-600}}"

system_slug="$(printf '%s' "$system_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
system_slug="${system_slug:-openami-guard}"

source_ami_name_pattern="${SOURCE_AMI_NAME_PATTERN:-}"
source_ami_owner="${SOURCE_AMI_OWNER:-}"
source_ami_ssh_username="${SOURCE_AMI_SSH_USERNAME:-}"
source_ami_virtualization_type="${SOURCE_AMI_VIRTUALIZATION_TYPE:-hvm}"
source_ami_root_device_type="${SOURCE_AMI_ROOT_DEVICE_TYPE:-ebs}"

case "${base_image_type}:${base_image_version}" in
  ubuntu:24.04)
    source_ami_name_pattern="${source_ami_name_pattern:-ubuntu/images/hvm-ssd/ubuntu-*-24.04-amd64-server-*}"
    source_ami_owner="${source_ami_owner:-099720109477}"
    source_ami_ssh_username="${source_ami_ssh_username:-ubuntu}"
    ;;
esac

ami_parameter_name="${AMI_PARAMETER_NAME:-/${system_slug}/current_ami_id}"
last_known_good_parameter_name="${LAST_KNOWN_GOOD_PARAMETER_NAME:-/${system_slug}/last_known_good_ami_id}"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    printf 'SYSTEM_NAME=%s\n' "$system_name"
    printf 'OPENAMI_SYSTEM_SLUG=%s\n' "$system_slug"
    printf 'BASE_IMAGE_TYPE=%s\n' "$base_image_type"
    printf 'BASE_IMAGE_VERSION=%s\n' "$base_image_version"
    printf 'SEVERITY_THRESHOLD=%s\n' "$severity_threshold"
    printf 'CANARY_PERCENTAGE=%s\n' "$canary_percentage"
    printf 'BAKE_TIME_SECONDS=%s\n' "$bake_time"
    printf 'AMI_PARAMETER_NAME=%s\n' "$ami_parameter_name"
    printf 'LAST_KNOWN_GOOD_PARAMETER_NAME=%s\n' "$last_known_good_parameter_name"
    printf 'SOURCE_AMI_NAME_PATTERN=%s\n' "$source_ami_name_pattern"
    printf 'SOURCE_AMI_OWNER=%s\n' "$source_ami_owner"
    printf 'SOURCE_AMI_SSH_USERNAME=%s\n' "$source_ami_ssh_username"
    printf 'SOURCE_AMI_VIRTUALIZATION_TYPE=%s\n' "$source_ami_virtualization_type"
    printf 'SOURCE_AMI_ROOT_DEVICE_TYPE=%s\n' "$source_ami_root_device_type"
  } >> "$GITHUB_ENV"

  if [[ -n "$slack_webhook" ]]; then
    printf 'SLACK_WEBHOOK=%s\n' "$slack_webhook" >> "$GITHUB_ENV"
  fi
fi

echo "[INFO] Loaded OpenAMI config from ${CONFIG_FILE}"
echo "[INFO] System: ${system_name}"
echo "[INFO] Base image: ${base_image_type} ${base_image_version}"
echo "[INFO] Severity threshold: ${severity_threshold}"
echo "[INFO] Canary percentage: ${canary_percentage}"
echo "[INFO] Bake time: ${bake_time}"
