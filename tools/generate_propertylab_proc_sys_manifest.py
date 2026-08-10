#!/usr/bin/env python3
"""Generate a temporary PropertyLab manifest from one profile's apply_param_set data.

The generated data contains only literal /proc/sys writes declared by the chosen
net profile. It does not execute or source the profile, and it does not include
properties, WCNSS overlays, framework Wi-Fi commands, or service-startup writes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


PROFILES = {
    "stable": "stable_profile.sh",
    "speed": "speed_profile.sh",
    "gaming": "gaming_profile.sh",
    "benchmark_gaming": "benchmark_gaming_profile.sh",
    "benchmark_speed": "benchmark_speed_profile.sh",
}
HERE_DOC_START = re.compile(r"^\s*apply_param_set\s+<<'EOF'\s*$")
ENTRY = re.compile(r"^([^|\r\n]+)\|(/proc/sys/[A-Za-z0-9_./-]+)\|([^|\r\n]+)$")


def repository_revision(repo: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def extract_operations(path: Path) -> list[dict[str, str | int]]:
    operations: list[dict[str, str | int]] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    index = 0
    block = 0
    while index < len(lines):
        if not HERE_DOC_START.match(lines[index]):
            index += 1
            continue
        block += 1
        index += 1
        entries = 0
        while index < len(lines) and lines[index] != "EOF":
            raw = lines[index]
            index += 1
            if not raw or raw.lstrip().startswith("#"):
                continue
            match = ENTRY.fullmatch(raw)
            if match is None:
                raise ValueError(f"invalid apply_param_set entry in {path.name}: {raw!r}")
            value, proc_path, description = match.groups()
            if "\t" in value or "\t" in description:
                raise ValueError(f"tab is not supported in {path.name}: {raw!r}")
            entries += 1
            operations.append(
                {
                    "operation": "proc_sys_write",
                    "path": proc_path,
                    "value": value,
                    "description": description,
                    "source_block": block,
                    "source_line": index,
                }
            )
        if index == len(lines):
            raise ValueError(f"unterminated apply_param_set block in {path.name}")
        if entries == 0:
            raise ValueError(f"empty apply_param_set block in {path.name}")
        index += 1
    if not operations:
        raise ValueError(f"no apply_param_set data found in {path.name}")
    paths = [str(operation["path"]) for operation in operations]
    if len(paths) != len(set(paths)):
        raise ValueError(f"duplicate /proc/sys target in {path.name}")
    return operations


def build_manifest(repo: Path, profile: str) -> dict[str, object]:
    source_path = repo / "net_profiles" / PROFILES[profile]
    return {
        "schema": 1,
        "mode": "research_temporary",
        "release_eligible": False,
        "experiment_id": f"plps-{profile.replace('_', '-')}-v1",
        "mechanism": "apply_param_set_proc_sys_only",
        "source_commit": repository_revision(repo),
        "source_sha256": {str(source_path.relative_to(repo)): hashlib.sha256(source_path.read_bytes()).hexdigest()},
        "profile_source": profile,
        "scope": "literal_apply_param_set_proc_sys_entries_only",
        "excluded": [
            "resetprop",
            "setprop",
            "system.prop",
            "service_startup_apply_param_set",
            "WCNSS",
            "file_overlays",
            "settings",
            "cmd_wifi",
            "ndc",
            "dynamic_values",
        ],
        "operations": extract_operations(source_path),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=tuple(PROFILES), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    repo = Path(__file__).resolve().parent.parent
    manifest = build_manifest(repo, args.profile)
    serialized = json.dumps(manifest, ensure_ascii=True, indent=2) + "\n"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(serialized, encoding="utf-8")
    digest = hashlib.sha256(serialized.encode("utf-8")).hexdigest()
    digest_file = args.output.with_suffix(args.output.suffix + ".sha256")
    digest_file.write_text(f"{digest}  {args.output.name}\n", encoding="utf-8")
    print(f"experiment_id={manifest['experiment_id']}")
    print(f"operations={len(manifest['operations'])}")
    print(f"manifest_sha256={digest}")
    print(f"manifest_sha256_file={digest_file}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"[ERROR] {exc}")
        raise SystemExit(1)
