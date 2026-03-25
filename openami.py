#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parent
DEFAULT_CONFIG = ROOT / "openami.yaml"
DEFAULT_STATUS = ROOT / "dashboard" / "status.json"
DEFAULT_EXPLAIN = ROOT / "dashboard" / "explain-report.json"
DEFAULT_WORKFLOW = ".github/workflows/self-healing-ami.yml"


def parse_openami_yaml(path: Path) -> dict:
    if not path.exists():
        return {}

    data: dict[str, object] = {}
    section: str | None = None

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        if not line.startswith(" ") and stripped.endswith(":"):
            section = stripped[:-1]
            data.setdefault(section, {})
            continue

        if ":" not in stripped:
            continue

        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")

        parsed: object = value
        if value.isdigit():
            parsed = int(value)

        if line.startswith(" ") and section:
            section_map = data.setdefault(section, {})
            if isinstance(section_map, dict):
                section_map[key] = parsed
        else:
            data[key] = parsed

    return data


def load_json(path: Path) -> object:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def print_kv(key: str, value: object) -> None:
    print(f"{key}: {value}")


def normalize_text(value: object, default: str = "unknown") -> str:
    if value is None:
        return default
    text = str(value).strip()
    return text or default


def normalize_int(value: object, default: int = 0) -> int:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value.strip())
        except ValueError:
            return default
    return default


def explain_packages(explain: dict) -> str:
    packages = explain.get("affected_packages", [])
    if isinstance(packages, list):
        normalized = [normalize_text(item, "") for item in packages]
        filtered = [item for item in normalized if item]
        return ", ".join(filtered) if filtered else "none"
    return normalize_text(packages, "none")


def print_explain_mode(explain: dict) -> None:
    print("Explain mode")
    print("------------")
    print_kv("Reason", explain.get("reason", "unknown"))
    print_kv("Affected packages", explain_packages(explain))
    print_kv("Action taken", explain.get("action_taken", "unknown"))
    print_kv("Confidence", explain.get("confidence", "unknown"))

    has_risk_trend = any(
        key in explain
        for key in ("previous_score", "new_score", "delta")
    )
    if has_risk_trend:
        print()
        print("Risk score trend")
        print("----------------")
        print_kv("Previous score", explain.get("previous_score", "unknown"))
        print_kv("New score", explain.get("new_score", "unknown"))
        print_kv("Delta", explain.get("delta", "unknown"))


def parse_timestamp(value: object) -> datetime | None:
    if not value:
        return None

    text = str(value).strip()
    if not text:
        return None

    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None


def is_incident_status(status: object) -> bool:
    normalized = normalize_text(status, "").lower()
    return any(
        marker in normalized
        for marker in ("incident", "rollback", "failed", "unhealthy", "degraded")
    )


def is_healthy_status(status: object) -> bool:
    normalized = normalize_text(status, "").lower()
    return any(
        marker in normalized
        for marker in ("healthy", "stable", "promoted", "current", "success")
    )


def lineage_history(status: dict) -> list[dict[str, object]]:
    lineage_dates: dict[str, object] = {}
    raw_lineage = status.get("amiLineage")
    if isinstance(raw_lineage, list):
        for item in raw_lineage:
            if isinstance(item, dict):
                ami_id = normalize_text(item.get("amiId"), "")
                if ami_id:
                    lineage_dates[ami_id] = item.get("createdAt")

    history: list[dict[str, object]] = []
    intelligence = status.get("amiLineageIntelligence")
    raw_history = []
    if isinstance(intelligence, dict):
        possible_history = intelligence.get("history")
        if isinstance(possible_history, list):
            raw_history = possible_history
    elif isinstance(status.get("amiHistory"), list):
        raw_history = status.get("amiHistory")

    for item in raw_history:
        if not isinstance(item, dict):
            continue

        ami_version = normalize_text(
            item.get("ami_version") or item.get("amiVersion") or item.get("amiId")
        )
        history.append(
            {
                "ami_version": ami_version,
                "parent_ami": normalize_text(item.get("parent_ami") or item.get("parentAmi")),
                "change_reason": normalize_text(item.get("change_reason") or item.get("changeReason")),
                "deployment_status": normalize_text(item.get("deployment_status") or item.get("deploymentStatus")),
                "rollback_count": normalize_int(item.get("rollback_count") or item.get("rollbackCount")),
                "deployed_at": normalize_text(
                    item.get("deployed_at")
                    or item.get("deployedAt")
                    or lineage_dates.get(ami_version)
                ),
            }
        )

    if history:
        return history

    raw_lineage_list = status.get("amiLineage")
    if not isinstance(raw_lineage_list, list):
        return []

    previous_ami = "none"
    for item in raw_lineage_list:
        if not isinstance(item, dict):
            continue
        ami_version = normalize_text(item.get("amiId"))
        history.append(
            {
                "ami_version": ami_version,
                "parent_ami": previous_ami,
                "change_reason": normalize_text(item.get("source")),
                "deployment_status": normalize_text(item.get("status")),
                "rollback_count": 0,
                "deployed_at": normalize_text(item.get("createdAt")),
            }
        )
        previous_ami = ami_version

    return history


def build_lineage_intelligence(status: dict) -> dict[str, object]:
    history = lineage_history(status)
    if not history:
        return {
            "history": [],
            "incident_amis": [],
            "most_stable_ami": "unknown",
            "patch_frequency": "unknown",
        }

    incident_amis = [
        item["ami_version"]
        for item in history
        if is_incident_status(item.get("deployment_status")) or normalize_int(item.get("rollback_count")) > 0
    ]

    ranked_history = sorted(
        history,
        key=lambda item: (
            0 if is_healthy_status(item.get("deployment_status")) else 1,
            0 if not is_incident_status(item.get("deployment_status")) else 1,
            normalize_int(item.get("rollback_count")),
            -(parse_timestamp(item.get("deployed_at")).timestamp()) if parse_timestamp(item.get("deployed_at")) else float("inf"),
        ),
    )
    most_stable_ami = ranked_history[0]["ami_version"] if ranked_history else "unknown"

    patch_times = sorted(
        [stamp for stamp in (parse_timestamp(item.get("deployed_at")) for item in history) if stamp]
    )
    patch_frequency = "unknown"
    if len(patch_times) >= 2:
        day_gaps = [
            (patch_times[index] - patch_times[index - 1]).total_seconds() / 86400
            for index in range(1, len(patch_times))
        ]
        average_days = sum(day_gaps) / len(day_gaps)
        patch_frequency = f"every {average_days:.1f} days on average"
    elif len(patch_times) == 1:
        patch_frequency = "single tracked deployment so far"

    return {
        "history": history,
        "incident_amis": incident_amis,
        "most_stable_ami": most_stable_ami,
        "patch_frequency": patch_frequency,
    }


def print_lineage_intelligence(status: dict) -> None:
    intelligence = build_lineage_intelligence(status)
    print("AMI lineage intelligence")
    print("----------------------")
    incident_amis = intelligence.get("incident_amis", [])
    print_kv("AMI(s) causing incidents", ", ".join(incident_amis) if incident_amis else "none tracked")
    print_kv("Most stable AMI", intelligence.get("most_stable_ami", "unknown"))
    print_kv("Patching frequency", intelligence.get("patch_frequency", "unknown"))
    print()

    history = intelligence.get("history", [])
    if not history:
        print("No AMI lineage history found in dashboard/status.json")
        return

    print("Tracked AMI history")
    print("-------------------")
    for item in history:
        print(
            f"- {item['ami_version']} | parent={item['parent_ami']} | "
            f"reason={item['change_reason']} | status={item['deployment_status']} | "
            f"rollbacks={item['rollback_count']} | deployed={item['deployed_at']}"
        )
    print()


def command_status(_: argparse.Namespace) -> int:
    config = parse_openami_yaml(DEFAULT_CONFIG)
    status = load_json(DEFAULT_STATUS)
    explain = load_json(DEFAULT_EXPLAIN)
    if not isinstance(status, dict):
        status = {}
    if not isinstance(explain, dict):
        explain = {}

    system_name = status.get("systemName") or config.get("system") or "openami-guard"
    print(system_name)
    print("=" * len(str(system_name)))

    if config:
        print_kv("Base image", f"{config.get('base_image', {}).get('type', 'unknown')} {config.get('base_image', {}).get('version', 'unknown')}")
        print_kv("Severity threshold", config.get("security", {}).get("severity_threshold", "unknown"))
        print_kv("Canary percentage", config.get("rollout", {}).get("canary_percentage", "unknown"))
        print_kv("Bake time", config.get("rollout", {}).get("bake_time", "unknown"))
        print()

    if status:
        print("Infra health")
        print("-----------")
        print_kv("Current AMI", status.get("currentAmiVersion", "unknown"))
        print_kv("Vulnerability status", status.get("vulnerabilityStatus", "unknown"))
        print_kv("Rollout status", status.get("rolloutStatus", "unknown"))
        print_kv("Last patch time", status.get("lastPatchTime", "unknown"))
        print_kv("Pipeline reason", status.get("pipelineReason", "unknown"))
        print_kv("Generated at", status.get("generatedAt", "unknown"))
        print()
    else:
        print("No dashboard status found at dashboard/status.json")
        print()

    print_lineage_intelligence(status)

    if explain:
        print_explain_mode(explain)
    else:
        print("No explain report found at dashboard/explain-report.json")

    return 0


def command_lineage(_: argparse.Namespace) -> int:
    status = load_json(DEFAULT_STATUS)
    if not isinstance(status, dict):
        status = {}
    print_lineage_intelligence(status)
    return 0


def ensure_gh() -> str:
    gh = shutil.which("gh")
    if not gh:
        raise RuntimeError(
            "GitHub CLI (`gh`) is required for this command. Install it and run `gh auth login`."
        )
    return gh


def run_workflow(force_rebuild: bool, skip_rollout: bool) -> int:
    gh = ensure_gh()
    cmd = [
        gh,
        "workflow",
        "run",
        DEFAULT_WORKFLOW,
        "-f",
        f"force_rebuild={'true' if force_rebuild else 'false'}",
        "-f",
        f"skip_rollout={'true' if skip_rollout else 'false'}",
    ]
    completed = subprocess.run(cmd, cwd=ROOT, check=False)
    return completed.returncode


def command_rebuild(args: argparse.Namespace) -> int:
    print("Triggering rebuild workflow...")
    return run_workflow(force_rebuild=True, skip_rollout=args.skip_rollout)


def command_rollout(args: argparse.Namespace) -> int:
    print("Triggering rollout workflow...")
    return run_workflow(force_rebuild=args.force_rebuild, skip_rollout=False)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="openami", description="OpenAMI Guard CLI")
    subparsers = parser.add_subparsers(dest="command", required=True)

    status_parser = subparsers.add_parser("status", help="Show current AMI and infra health")
    status_parser.set_defaults(func=command_status)

    rebuild_parser = subparsers.add_parser("rebuild", help="Force a rebuild through GitHub Actions")
    rebuild_parser.add_argument("--skip-rollout", action="store_true", help="Build and validate only")
    rebuild_parser.set_defaults(func=command_rebuild)

    rollout_parser = subparsers.add_parser("rollout", help="Start the standard rollout workflow")
    rollout_parser.add_argument("--force-rebuild", action="store_true", help="Rebuild before rollout")
    rollout_parser.set_defaults(func=command_rollout)

    lineage_parser = subparsers.add_parser("lineage", help="Show AMI lineage intelligence and history")
    lineage_parser.set_defaults(func=command_lineage)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
