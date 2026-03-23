#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
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


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def print_kv(key: str, value: object) -> None:
    print(f"{key}: {value}")


def command_status(_: argparse.Namespace) -> int:
    config = parse_openami_yaml(DEFAULT_CONFIG)
    status = load_json(DEFAULT_STATUS)
    explain = load_json(DEFAULT_EXPLAIN)

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

    if explain:
        print("Explain mode")
        print("------------")
        print_kv("Reason", explain.get("reason", "unknown"))
        print_kv("Affected packages", ", ".join(explain.get("affected_packages", [])) or "none")
        print_kv("Action taken", explain.get("action_taken", "unknown"))
        print_kv("Confidence", explain.get("confidence", "unknown"))
    else:
        print("No explain report found at dashboard/explain-report.json")

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
