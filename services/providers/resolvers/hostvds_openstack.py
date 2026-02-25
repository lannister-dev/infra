from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from typing import Any

from services.providers.resolvers.common import find_ips, find_region, is_ipv4, is_public_ipv4


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def request_json(
    method: str,
    url: str,
    headers: dict[str, str],
    payload: dict[str, Any] | None = None,
    fatal: bool = True,
) -> tuple[dict[str, Any] | None, dict[str, str]]:
    body = None
    local_headers = dict(headers)
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        local_headers["Content-Type"] = "application/json"

    request = urllib.request.Request(url=url, headers=local_headers, method=method, data=body)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode("utf-8")
            data = json.loads(raw) if raw else {}
            response_headers = dict(response.headers.items())
            return data, response_headers
    except urllib.error.HTTPError as exc:
        body = ""
        try:
            body = exc.read().decode("utf-8", errors="replace").strip()
        except Exception:
            body = ""
        detail = f"HTTP {exc.code}" + (f" body={body}" if body else "")
        if fatal:
            fail(f"API request failed: {method} {url} -> {detail}")
        return None, {"__error__": detail}
    except urllib.error.URLError as exc:
        if fatal:
            fail(f"API request failed: {method} {url} -> {exc}")
        return None, {"__error__": str(exc)}
    except json.JSONDecodeError as exc:
        if fatal:
            fail(f"API response is not valid JSON for {method} {url}: {exc}")
        return None, {"__error__": f"JSON decode error: {exc}"}


def with_domain_ref(name: str, domain_name: str, domain_id: str) -> dict[str, Any]:
    if domain_id:
        return {"name": name, "domain": {"id": domain_id}}
    return {"name": name, "domain": {"name": domain_name}}


def build_keystone_auth_payload(query: dict[str, str]) -> dict[str, Any]:
    user_domain_name = query.get("os_user_domain_name", "")
    user_domain_id = query.get("os_user_domain_id", "")
    project_domain_name = query.get("os_project_domain_name", "")
    project_domain_id = query.get("os_project_domain_id", "")

    return {
        "auth": {
            "identity": {
                "methods": ["password"],
                "password": {
                    "user": {
                        **with_domain_ref(query["os_username"], user_domain_name, user_domain_id),
                        "password": query["os_password"],
                    }
                },
            },
            "scope": {
                "project": with_domain_ref(query["os_project_name"], project_domain_name, project_domain_id)
            },
        }
    }


def find_compute_endpoints(
    catalog: list[dict[str, Any]], interface: str, preferred_region: str
) -> list[tuple[str, str]]:
    endpoints: list[tuple[str, str]] = []
    for service in catalog:
        if service.get("type") != "compute":
            continue
        for endpoint in service.get("endpoints", []):
            if endpoint.get("interface") != interface:
                continue
            endpoint_region = (endpoint.get("region") or endpoint.get("region_id") or "").strip()
            url = (endpoint.get("url") or "").strip()
            if url:
                endpoints.append((url, endpoint_region))

    if not endpoints:
        fail("Could not find compute endpoint in Keystone catalog")

    if not preferred_region:
        return endpoints

    preferred = [endpoint for endpoint in endpoints if endpoint[1] == preferred_region]
    fallback = [endpoint for endpoint in endpoints if endpoint[1] != preferred_region]
    return preferred + fallback


def extract_server_ipv4(server_payload: dict[str, Any]) -> str:
    server = server_payload.get("server", {})
    addresses = server.get("addresses", {})
    all_candidates: list[str] = []
    floating_candidates: list[str] = []

    for ip_entries in addresses.values():
        if not isinstance(ip_entries, list):
            continue
        for entry in ip_entries:
            if not isinstance(entry, dict):
                continue
            addr = str(entry.get("addr", "")).strip()
            if not is_ipv4(addr):
                continue
            all_candidates.append(addr)
            ip_type = str(entry.get("OS-EXT-IPS:type", "")).strip().lower()
            if ip_type == "floating":
                floating_candidates.append(addr)

    if floating_candidates:
        for ip in floating_candidates:
            if is_public_ipv4(ip):
                return ip
        return floating_candidates[0]

    if all_candidates:
        public_candidates = [ip for ip in all_candidates if is_public_ipv4(ip)]
        return public_candidates[0] if public_candidates else all_candidates[0]

    ips = find_ips(server_payload)
    public_ips = [ip for ip in ips if is_public_ipv4(ip)]
    chosen_ip = public_ips[0] if public_ips else (ips[0] if ips else "")
    if chosen_ip:
        return chosen_ip
    fail("Could not extract IPv4 address from OpenStack server payload")


def resolve(query: dict[str, Any]) -> dict[str, str]:
    os_auth_url = str(query.get("os_auth_url", "")).strip()
    os_username = str(query.get("os_username", "")).strip()
    os_password = str(query.get("os_password", "")).strip()
    os_project_name = str(query.get("os_project_name", "")).strip()
    os_user_domain_name = str(query.get("os_user_domain_name", "")).strip()
    os_user_domain_id = str(query.get("os_user_domain_id", "")).strip()
    os_project_domain_name = str(query.get("os_project_domain_name", "")).strip()
    os_project_domain_id = str(query.get("os_project_domain_id", "")).strip()
    os_region_name = str(query.get("os_region_name", "")).strip()
    os_interface = str(query.get("os_interface", "")).strip()
    server_id = str(query.get("server_id", "")).strip()

    if not os_auth_url:
        fail("os_auth_url is required")
    if not os_username:
        fail("os_username is required")
    if not os_password:
        fail("os_password is required")
    if not os_project_name:
        fail("os_project_name is required")
    if not os_interface:
        fail("os_interface is required")
    if not (os_user_domain_name or os_user_domain_id):
        fail("set os_user_domain_name or os_user_domain_id")
    if not (os_project_domain_name or os_project_domain_id):
        fail("set os_project_domain_name or os_project_domain_id")
    if not server_id:
        fail("server_id is required")

    normalized_query = {
        "os_username": os_username,
        "os_password": os_password,
        "os_project_name": os_project_name,
        "os_user_domain_name": os_user_domain_name,
        "os_user_domain_id": os_user_domain_id,
        "os_project_domain_name": os_project_domain_name,
        "os_project_domain_id": os_project_domain_id,
    }

    auth_base = os_auth_url.rstrip("/")
    keystone_candidates = [f"{auth_base}/auth/tokens"]
    if not auth_base.endswith("/v3") and not auth_base.endswith("v3"):
        keystone_candidates.insert(0, f"{auth_base}/v3/auth/tokens")

    auth_payload = build_keystone_auth_payload(normalized_query)
    auth_response: dict[str, Any] | None = None
    auth_headers: dict[str, str] = {}
    auth_errors: list[str] = []
    for keystone_url in keystone_candidates:
        auth_response, auth_headers = request_json(
            "POST",
            keystone_url,
            {"Accept": "application/json"},
            auth_payload,
            fatal=False,
        )
        if auth_response is not None:
            break
        auth_errors.append(f"{keystone_url}: {auth_headers.get('__error__', 'unknown error')}")

    if auth_response is None:
        fail("Keystone auth failed for all candidate URLs: " + "; ".join(auth_errors))

    token = auth_headers.get("X-Subject-Token") or auth_headers.get("x-subject-token")
    if not token:
        fail("Keystone auth succeeded but X-Subject-Token header is missing")

    catalog = auth_response.get("token", {}).get("catalog", [])
    compute_endpoints = find_compute_endpoints(catalog, os_interface, os_region_name)
    server_payload: dict[str, Any] | None = None
    resolved_region = ""
    lookup_errors: list[str] = []
    for compute_base_url, endpoint_region in compute_endpoints:
        server_url = f"{compute_base_url.rstrip('/')}/servers/{server_id}"
        payload, error_headers = request_json(
            "GET",
            server_url,
            {"Accept": "application/json", "X-Auth-Token": token},
            fatal=False,
        )
        if payload is not None:
            server_payload = payload
            resolved_region = endpoint_region
            break
        lookup_errors.append(f"{server_url}: {error_headers.get('__error__', 'unknown error')}")

    if server_payload is None:
        fail(
            "Could not resolve server by id in available compute endpoints. "
            f"server_id={server_id}; attempts: {'; '.join(lookup_errors)}"
        )

    chosen_ip = extract_server_ipv4(server_payload)

    region = resolved_region if resolved_region else os_region_name
    if not region:
        region = find_region(server_payload)

    return {"public_ip": chosen_ip, "region": region}


def main() -> None:
    try:
        query = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        fail(f"Invalid external query JSON: {exc}")
    print(json.dumps(resolve(query)))


if __name__ == "__main__":
    main()
