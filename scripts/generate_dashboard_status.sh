#!/usr/bin/env bash
set -euo pipefail

OUTPUT_PATH="${1:-dashboard/status.json}"
mkdir -p "$(dirname "$OUTPUT_PATH")"

SYSTEM_NAME="${SYSTEM_NAME:-OpenAMI Guard}"
CURRENT_AMI_VERSION="${CURRENT_AMI_VERSION:-unknown}"
VULNERABILITY_STATUS="${VULNERABILITY_STATUS:-unknown}"
LAST_PATCH_TIME="${LAST_PATCH_TIME:-unknown}"
ROLLOUT_STATUS="${ROLLOUT_STATUS:-idle}"
PIPELINE_REASON="${PIPELINE_REASON:-none}"
LAST_KNOWN_GOOD_AMI="${LAST_KNOWN_GOOD_AMI:-unknown}"
CANARY_INSTANCE_REFRESH_ID="${CANARY_INSTANCE_REFRESH_ID:-n/a}"
GENERATED_AT="${GENERATED_AT:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
AMI_LINEAGE_JSON="${AMI_LINEAGE_JSON:-[]}"
AMI_LINEAGE_INTELLIGENCE_JSON="${AMI_LINEAGE_INTELLIGENCE_JSON:-{\"history\":[],\"incident_amis\":[],\"most_stable_ami\":\"unknown\",\"patch_frequency\":\"unknown\"}}"
VULNERABILITY_TRENDS_JSON="${VULNERABILITY_TRENDS_JSON:-[]}"
ROLLOUT_TIMELINE_JSON="${ROLLOUT_TIMELINE_JSON:-[]}"
CANARY_ANALYTICS_JSON="${CANARY_ANALYTICS_JSON:-{\"successRate\":null,\"successfulRuns\":0,\"totalRuns\":0,\"recentRuns\":[]}}"

cat > "$OUTPUT_PATH" <<EOF
{
  "systemName": "${SYSTEM_NAME}",
  "currentAmiVersion": "${CURRENT_AMI_VERSION}",
  "vulnerabilityStatus": "${VULNERABILITY_STATUS}",
  "lastPatchTime": "${LAST_PATCH_TIME}",
  "rolloutStatus": "${ROLLOUT_STATUS}",
  "pipelineReason": "${PIPELINE_REASON}",
  "lastKnownGoodAmi": "${LAST_KNOWN_GOOD_AMI}",
  "canaryInstanceRefreshId": "${CANARY_INSTANCE_REFRESH_ID}",
  "generatedAt": "${GENERATED_AT}",
  "amiLineage": ${AMI_LINEAGE_JSON},
  "amiLineageIntelligence": ${AMI_LINEAGE_INTELLIGENCE_JSON},
  "vulnerabilityTrends": ${VULNERABILITY_TRENDS_JSON},
  "rolloutTimeline": ${ROLLOUT_TIMELINE_JSON},
  "canaryAnalytics": ${CANARY_ANALYTICS_JSON}
}
EOF

echo "[INFO] Dashboard status written to ${OUTPUT_PATH}"
