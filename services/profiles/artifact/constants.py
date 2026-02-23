from __future__ import annotations

from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[3]
XRAY_TEMPLATE_DEFAULT = ROOT_DIR / "vpn" / "xray" / "config.json.j2"
XRAY_OVERRIDES_DEFAULT = ROOT_DIR / "vpn" / "xray" / "artifact.overrides.yml"
ARTIFACT_OUTPUT_DEFAULT = ROOT_DIR / "artifacts" / "profiles" / "artifact.json"

SUPPORTED_PROFILE_TYPES = {"ws_tls", "reality_tcp"}
