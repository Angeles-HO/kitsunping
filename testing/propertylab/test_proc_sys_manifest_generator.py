#!/usr/bin/env python3

import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
GENERATOR = REPO / "tools" / "generate_propertylab_proc_sys_manifest.py"


def main() -> int:
    with tempfile.TemporaryDirectory() as temporary:
        output = Path(temporary) / "manifest.json"
        result = subprocess.run(
            [sys.executable, str(GENERATOR), "--profile", "benchmark_gaming", "--output", str(output)],
            check=True,
            capture_output=True,
            text=True,
        )
        manifest = json.loads(output.read_text(encoding="utf-8"))
        digest = output.with_suffix(".json.sha256").read_text(encoding="utf-8").split()[0]

    assert manifest["experiment_id"] == "plps-benchmark-gaming-v1"
    assert manifest["mechanism"] == "apply_param_set_proc_sys_only"
    assert manifest["profile_source"] == "benchmark_gaming"
    assert manifest["excluded"] == ["resetprop", "setprop", "system.prop", "service_startup_apply_param_set", "WCNSS", "file_overlays", "settings", "cmd_wifi", "ndc", "dynamic_values"]
    assert len(manifest["operations"]) == 36
    assert all(item["operation"] == "proc_sys_write" for item in manifest["operations"])
    assert all(str(item["path"]).startswith("/proc/sys/") for item in manifest["operations"])
    assert all("description" in item and "value" in item for item in manifest["operations"])
    assert manifest["operations"][0]["path"] == "/proc/sys/net/core/bpf_jit_enable"
    assert manifest["operations"][0]["value"] == "1"
    assert manifest["operations"][-1]["path"] == "/proc/sys/net/ipv4/tcp_tw_reuse"
    assert f"manifest_sha256={digest}" in result.stdout
    assert len(digest) == 64
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
