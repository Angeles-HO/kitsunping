#!/usr/bin/env python3
"""Generate a local-only, source-derived PropertyLab research manifest.

This generator is deliberately separate from the release module. It inventories
only static property values declared in current source for one profile/SoC
variant. It excludes calibration, BEST_* values, sysctl writes, file overlays,
and WCNSS.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


SYSTEM_PROP_PREFIXES = (
    "ro.ril.",
    "ro.telephony.",
    "ro.wifi.",
    "net.",
    "persist.vendor.",
    "persist.sys.",
    "persist.radio.",
    "ro.config.",
    "persist.audio.",
)
SYSTEM_PROP_KEYS = {"logcat.live"}
EXCLUDED_KEY_PREFIXES = ("persist.kitsunping.", "kitsunping.", "persist.kitsunrouter.", "kitsunrouter.")
PROP_LINE = re.compile(r'^\s*apply_prop\s+"([A-Za-z0-9._-]+)"\s+"([^"]*)"\s*$')
CASE_START = re.compile(r'^\s*case\s+"\$profile_name"\s+in\s*$')
CASE_ARM = re.compile(r'^\s*([A-Za-z0-9_|-]+)\)\s*$')


def repository_revision(repo: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def parse_system_properties(path: Path) -> list[tuple[str, str]]:
    properties: list[tuple[str, str]] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        if key.startswith(EXCLUDED_KEY_PREFIXES):
            continue
        if key in SYSTEM_PROP_KEYS or key.startswith(SYSTEM_PROP_PREFIXES):
            properties.append((key, value))
    return properties


def function_lines(source: str, marker: str) -> list[str]:
    start = source.find(marker)
    if start < 0:
        raise ValueError(f"missing source marker: {marker}")
    next_section = source.find("\n# Normaliza valores", start)
    if next_section < 0:
        raise ValueError("missing profile function boundary")
    return source[start:next_section].splitlines()


def case_properties(lines: list[str], profile: str, start_at: int = 0) -> list[tuple[str, str]]:
    case_index = next((index for index, line in enumerate(lines[start_at:], start_at) if CASE_START.match(line)), None)
    if case_index is None:
        raise ValueError("missing profile case block")

    selected = False
    result: list[tuple[str, str]] = []
    for line in lines[case_index + 1 :]:
        if line.strip() == "esac":
            break
        arm = CASE_ARM.match(line)
        if arm:
            selected = profile in arm.group(1).split("|")
            continue
        if line.strip() == ";;":
            selected = False
            continue
        prop = PROP_LINE.match(line)
        if selected and prop:
            result.append(prop.groups())
    if not result:
        raise ValueError(f"no static properties found for profile={profile}")
    return result


def source_profile_properties(path: Path, profile: str, soc: str) -> list[tuple[str, str, str, str, str]]:
    lines = function_lines(path.read_text(encoding="utf-8"), "apply_profile_runtime_resetprops()")
    output = [(key, value, "runtime_profile", "profile_common", "all") for key, value in case_properties(lines, profile)]

    if soc == "qcom":
        qcom_index = next((index for index, line in enumerate(lines) if line.strip() == "if is_qualcomm; then"), None)
        if qcom_index is None:
            raise ValueError("missing Qualcomm profile block")
        output.extend((key, value, "runtime_profile", "profile_qcom", "qcom") for key, value in case_properties(lines, profile, qcom_index))
    elif soc != "mtk":
        raise ValueError(f"unsupported SoC branch: {soc}")
    else:
        mtk_index = next((index for index, line in enumerate(lines) if line.strip() == "if is_mtk; then"), None)
        if mtk_index is None:
            raise ValueError("missing MediaTek profile block")
        output.extend((key, value, "runtime_profile", "profile_mtk", "mtk") for key, value in case_properties(lines, profile, mtk_index))
    return output


def classify_risk(key: str) -> str:
    if key.startswith("ro.ril.") or key.startswith("ro.telephony."):
        return "radio_static"
    if key.startswith("persist.vendor.") or key.startswith("sys.wifi"):
        return "vendor_wifi_static"
    if key.startswith("net.") or key.startswith("sys.tcp"):
        return "tcp_static"
    if key.startswith("persist.data."):
        return "data_aggregation_static"
    return "external_static"


def add_operation(
    operations: dict[str, dict[str, object]],
    key: str,
    value: str,
    phase: str,
    source_symbol: str,
    device_gate: str,
) -> None:
    existing = operations.get(key)
    source = {"path": "system.prop" if phase == "magisk_system_prop" else "addon/functions/utils/Kitsutils.sh", "symbol": source_symbol}
    if existing is not None:
        if existing["value"] != value:
            raise ValueError(f"conflicting static values for {key}: {existing['value']!r} != {value!r}")
        existing["sources"].append(source)
        return

    operations[key] = {
        "operation": "resetprop",
        "phase": phase,
        "key": key,
        "value": value,
        "risk_class": classify_risk(key),
        "device_gate": device_gate,
        "sources": [source],
    }


def build_manifest(repo: Path, profile: str, soc: str) -> dict[str, object]:
    operations: dict[str, dict[str, object]] = {}
    system_prop_path = repo / "system.prop"
    profile_source_path = repo / "addon/functions/utils/Kitsutils.sh"
    for key, value in parse_system_properties(system_prop_path):
        add_operation(operations, key, value, "magisk_system_prop", "static_external_property", "all")
    for key, value, phase, symbol, gate in source_profile_properties(profile_source_path, profile, soc):
        add_operation(operations, key, value, phase, symbol, gate)

    return {
        "schema": 1,
        "mode": "research_temporary",
        "release_eligible": False,
        "experiment_id": f"plr-static-{profile}-{soc}-v1",
        "source_commit": repository_revision(repo),
        "source_sha256": {
            "system.prop": hashlib.sha256(system_prop_path.read_bytes()).hexdigest(),
            "addon/functions/utils/Kitsutils.sh": hashlib.sha256(profile_source_path.read_bytes()).hexdigest(),
        },
        "profile": profile,
        "soc_branch": soc,
        "scope": "static_known_property_values_only",
        "excluded": ["calibration", "BEST_*", "sysctl", "file_overlay", "WCNSS", "dynamic_values"],
        "required_result_fields": ["experiment_id", "applied_properties", "manifest_sha256", "result", "manual_observations"],
        "operations": list(operations.values()),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("stable", "speed", "gaming"), required=True)
    parser.add_argument("--soc", choices=("qcom", "mtk"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    repo = Path(__file__).resolve().parent.parent
    manifest = build_manifest(repo, args.profile, args.soc)
    serialized = json.dumps(manifest, ensure_ascii=True, indent=2, sort_keys=True) + "\n"
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
        print(f"[ERROR] {exc}", file=sys.stderr)
        raise SystemExit(1)