from __future__ import annotations

from typing import Any

from services.providers.resolvers import hostvds_openstack as resolver


def _base_query() -> dict[str, Any]:
    return {
        "os_auth_url": "https://os-api.hostvds.com/identity",
        "os_username": "hostvds-user",
        "os_password": "secret",
        "os_project_name": "hostvds-user",
        "os_user_domain_name": "Default",
        "os_user_domain_id": "",
        "os_project_domain_name": "",
        "os_project_domain_id": "default",
        "os_region_name": "eu-north1b",
        "os_interface": "public",
        "server_id": "srv-123",
    }


def test_resolve_falls_back_to_other_region_when_preferred_has_404(monkeypatch) -> None:
    def fake_request_json(
        method: str,
        url: str,
        headers: dict[str, str],
        payload: dict[str, Any] | None = None,
        fatal: bool = True,
    ) -> tuple[dict[str, Any] | None, dict[str, str]]:
        if method == "POST" and "auth/tokens" in url:
            auth_payload = {
                "token": {
                    "catalog": [
                        {
                            "type": "compute",
                            "endpoints": [
                                {
                                    "interface": "public",
                                    "region": "eu-north1b",
                                    "url": "https://os-api.hostvds.com/eu-north1b/compute/v2.1/project",
                                },
                                {
                                    "interface": "public",
                                    "region": "eu-west2",
                                    "url": "https://os-api.hostvds.com/eu-west2/compute/v2.1/project",
                                },
                            ],
                        }
                    ]
                }
            }
            return auth_payload, {"X-Subject-Token": "token-123"}

        if method == "GET" and "eu-north1b" in url:
            return None, {"__error__": "HTTP 404"}

        if method == "GET" and "eu-west2" in url:
            server_payload = {
                "server": {
                    "addresses": {
                        "public": [
                            {"addr": "198.51.100.42", "OS-EXT-IPS:type": "floating"},
                        ]
                    }
                }
            }
            return server_payload, {}

        raise AssertionError(f"Unexpected request {method} {url}")

    monkeypatch.setattr(resolver, "request_json", fake_request_json)

    result = resolver.resolve(_base_query())

    assert result["public_ip"] == "198.51.100.42"
    assert result["region"] == "eu-west2"
