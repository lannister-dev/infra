from __future__ import annotations

from services.providers.resolvers import hostvds_openstack as hostvds


def test_extract_server_ipv4_prefers_public_floating_ip() -> None:
    payload = {
        "server": {
            "addresses": {
                "private-net": [
                    {"addr": "10.0.0.12", "OS-EXT-IPS:type": "fixed"},
                    {"addr": "8.8.8.8", "OS-EXT-IPS:type": "floating"},
                    {"addr": "1.1.1.1", "OS-EXT-IPS:type": "floating"},
                ]
            }
        }
    }

    assert hostvds.extract_server_ipv4(payload) == "8.8.8.8"


def test_extract_server_ipv4_uses_public_fixed_when_no_floating() -> None:
    payload = {
        "server": {
            "addresses": {
                "net-a": [
                    {"addr": "10.0.0.20", "OS-EXT-IPS:type": "fixed"},
                    {"addr": "8.8.4.4", "OS-EXT-IPS:type": "fixed"},
                ]
            }
        }
    }

    assert hostvds.extract_server_ipv4(payload) == "8.8.4.4"


def test_find_compute_endpoints_respects_region_and_interface() -> None:
    catalog = [
        {
            "type": "compute",
            "endpoints": [
                {"interface": "internal", "region": "eu-west2", "url": "https://internal.invalid"},
                {"interface": "public", "region": "eu-west2", "url": "https://compute.eu-west2.example"},
                {"interface": "public", "region": "ru-1", "url": "https://compute.ru-1.example"},
            ],
        }
    ]

    endpoints = hostvds.find_compute_endpoints(
        catalog,
        interface="public",
        preferred_region="eu-west2",
    )
    assert endpoints == [
        ("https://compute.eu-west2.example", "eu-west2"),
        ("https://compute.ru-1.example", "ru-1"),
    ]


def test_build_keystone_auth_payload_prefers_domain_ids() -> None:
    query = {
        "os_username": "user-1",
        "os_password": "secret",
        "os_project_name": "project-1",
        "os_user_domain_name": "Default",
        "os_user_domain_id": "user-domain-id",
        "os_project_domain_name": "Default",
        "os_project_domain_id": "project-domain-id",
    }

    payload = hostvds.build_keystone_auth_payload(query)
    user_domain = payload["auth"]["identity"]["password"]["user"]["domain"]
    project_domain = payload["auth"]["scope"]["project"]["domain"]

    assert user_domain == {"id": "user-domain-id"}
    assert project_domain == {"id": "project-domain-id"}
