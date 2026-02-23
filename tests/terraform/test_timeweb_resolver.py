from __future__ import annotations

import io
import json
import sys

from services.providers.resolvers import timeweb


def test_find_ips_extracts_nested_ipv4_values() -> None:
    payload = {
        "server": {
            "networking": {
                "v4": [{"address": "10.0.0.8"}, {"address": "203.0.113.30"}],
                "comment": "fallback: 198.51.100.70",
            }
        }
    }

    ips = timeweb.find_ips(payload)
    assert "10.0.0.8" in ips
    assert "203.0.113.30" in ips
    assert "198.51.100.70" in ips


def test_main_prefers_public_ipv4_and_preserves_region(monkeypatch, capsys) -> None:
    payload = {
        "server": {
            "region": "ru-msk",
            "interfaces": [
                {"ipv4": "10.10.0.12"},
                {"ipv4": "9.9.9.9"},
            ],
        }
    }

    def _fake_get_json(url: str, headers: dict[str, str]):  # noqa: ARG001
        return payload

    query = {
        "api_url": "https://api.timeweb.cloud/api/v1",
        "api_token": "test-token",
        "endpoint_template": "/servers/{server_id}",
        "server_id": "srv-123",
        "auth_header": "Authorization",
        "auth_scheme": "Bearer",
    }

    monkeypatch.setattr(timeweb, "get_json", _fake_get_json)
    monkeypatch.setattr(sys, "stdin", io.StringIO(json.dumps(query)))

    timeweb.main()
    result = json.loads(capsys.readouterr().out)

    assert result["public_ip"] == "9.9.9.9"
    assert result["region"] == "ru-msk"
