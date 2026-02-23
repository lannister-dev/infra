from __future__ import annotations

from pathlib import Path

import pytest

from services.profiles.artifact.builder import ArtifactBuilder
from services.profiles.artifact.errors import ArtifactBuildError

pytest.importorskip("yaml")


def _write(path: Path, content: str) -> Path:
    path.write_text(content, encoding="utf-8")
    return path


def test_build_artifact_success_for_ws_profile(tmp_path: Path) -> None:
    template = _write(
        tmp_path / "config.json.j2",
        """
{
  "inbounds": [
    {
      "tag": "api",
      "protocol": "dokodemo-door"
    },
    {
      "tag": "vless-ws",
      "protocol": "vless",
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/ws",
          "headers": {"Host": "vpn.example.com"}
        }
      }
    }
  ]
}
""".strip(),
    )

    overrides = _write(
        tmp_path / "artifact.overrides.yml",
        """
profiles:
  vless-ws:
    key: ws_tls_v1
    type: ws_tls
    display_name: CDN WS TLS
""".strip(),
    )

    artifact = ArtifactBuilder(strict=True).build_artifact(
        template_path=template,
        overrides_path=overrides,
    )

    assert artifact["ws_tls_v1"]["type"] == "ws_tls"
    assert artifact["ws_tls_v1"]["display_name"] == "CDN WS TLS"
    assert artifact["ws_tls_v1"]["client"]["path"] == "/ws"


def test_strict_mode_fails_on_unresolved_placeholders(tmp_path: Path) -> None:
    template = _write(
        tmp_path / "config.json.j2",
        """
{
  "inbounds": [
    {
      "tag": "vless-ws",
      "protocol": "vless",
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "${VPN_WS_PATH}",
          "headers": {"Host": "${VPN_DOMAIN}"}
        }
      }
    }
  ]
}
""".strip(),
    )

    overrides = _write(tmp_path / "artifact.overrides.yml", "profiles: {}")

    with pytest.raises(ArtifactBuildError, match="unresolved template placeholders"):
        ArtifactBuilder(strict=True).build_artifact(
            template_path=template,
            overrides_path=overrides,
        )


def test_non_strict_allows_unresolved_placeholders(tmp_path: Path) -> None:
    template = _write(
        tmp_path / "config.json.j2",
        """
{
  "inbounds": [
    {
      "tag": "vless-ws",
      "protocol": "vless",
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "${VPN_WS_PATH}",
          "headers": {"Host": "${VPN_DOMAIN}"}
        }
      }
    }
  ]
}
""".strip(),
    )

    overrides = _write(
        tmp_path / "artifact.overrides.yml",
        """
profiles:
  vless-ws:
    key: ws_tls_v1
    type: ws_tls
    display_name: CDN WS TLS
""".strip(),
    )

    artifact = ArtifactBuilder(strict=False).build_artifact(
        template_path=template,
        overrides_path=overrides,
    )

    assert artifact["ws_tls_v1"]["client"]["path"].startswith("/")


def test_fails_on_duplicate_profile_keys(tmp_path: Path) -> None:
    template = _write(
        tmp_path / "config.json.j2",
        """
{
  "inbounds": [
    {
      "tag": "vless-ws-a",
      "protocol": "vless",
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/a",
          "headers": {"Host": "a.example.com"}
        }
      }
    },
    {
      "tag": "vless-ws-b",
      "protocol": "vless",
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/b",
          "headers": {"Host": "b.example.com"}
        }
      }
    }
  ]
}
""".strip(),
    )

    overrides = _write(
        tmp_path / "artifact.overrides.yml",
        """
profiles:
  vless-ws-a:
    key: ws_tls_v1
    type: ws_tls
  vless-ws-b:
    key: ws_tls_v1
    type: ws_tls
""".strip(),
    )

    with pytest.raises(ArtifactBuildError, match="duplicate profile key"):
        ArtifactBuilder(strict=True).build_artifact(
            template_path=template,
            overrides_path=overrides,
        )


def test_reality_tcp_supports_spider_x_and_long_short_id(tmp_path: Path) -> None:
    template = _write(
        tmp_path / "config.json.j2",
        """
{
  "inbounds": [
    {
      "tag": "vless-reality",
      "protocol": "vless",
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverNames": ["www.cloudflare.com"],
          "shortIds": ["1234567890abcdef1234567890abcdef"]
        }
      }
    }
  ]
}
""".strip(),
    )

    overrides = _write(
        tmp_path / "artifact.overrides.yml",
        """
profiles:
  vless-reality:
    key: reality_tcp_v1
    type: reality_tcp
    display_name: Reality TCP
    client:
      fingerprint: chrome
      public_key: ABCDEFGHIJKLMNOP
      spider_x: /download
""".strip(),
    )

    artifact = ArtifactBuilder(strict=True).build_artifact(
        template_path=template,
        overrides_path=overrides,
    )

    reality = artifact["reality_tcp_v1"]["client"]
    assert reality["short_id"] == "1234567890abcdef1234567890abcdef"
    assert reality["spider_x"] == "/download"
