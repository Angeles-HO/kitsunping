#!/usr/bin/env python3

import json
import subprocess
import sys
import tempfile
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
GENERATOR = REPO / "tools" / "generate_propertylab_research_manifest.py"


def main() -> int:
    with tempfile.TemporaryDirectory() as temporary:
        output = Path(temporary) / "manifest.json"
        result = subprocess.run(
            [sys.executable, str(GENERATOR), "--profile", "speed", "--soc", "qcom", "--output", str(output)],
            check=True,
            capture_output=True,
            text=True,
        )
        manifest = json.loads(output.read_text(encoding="utf-8"))
        digest_file = output.with_suffix(output.suffix + ".sha256")
        digest = digest_file.read_text(encoding="utf-8").split()[0]

    assert "operations=" in result.stdout
    assert f"manifest_sha256={digest}" in result.stdout
    assert manifest["mode"] == "research_temporary"
    assert manifest["release_eligible"] is False
    assert manifest["experiment_id"] == "plr-static-speed-qcom-v1"
    assert manifest["excluded"] == ["calibration", "BEST_*", "sysctl", "file_overlay", "WCNSS", "dynamic_values"]
    assert set(manifest["source_sha256"]) == {"system.prop", "addon/functions/utils/Kitsutils.sh"}
    assert all(len(digest) == 64 for digest in manifest["source_sha256"].values())

    operations = {operation["key"]: operation for operation in manifest["operations"]}
    assert operations["persist.data.df.agg.dl_pkt"]["value"] == "20"
    assert operations["sys.wifi6.enable"]["value"] == "1"
    assert operations["persist.vendor.connmgr.wifi.bss_coloring"]["value"] == "1"
    assert operations["net.tcp_def_init_rwnd"]["value"] == "80"
    assert "ro.ril.hsupa.category" not in operations
    assert "ro.ril.hsdpa.category" not in operations
    assert "net.dns1" not in operations
    assert all(operation["operation"] == "resetprop" for operation in operations.values())
    assert all("sysctl" not in operation["operation"] for operation in operations.values())
    assert all("overlay" not in operation["operation"] for operation in operations.values())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())