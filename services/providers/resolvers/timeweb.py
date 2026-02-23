from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from typing import Any

from services.providers.resolvers.common import find_ips, find_region, is_public_ipv4


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def get_json(url: str, headers: dict[str, str]) -> dict[str, Any]:
    request = urllib.request.Request(url=url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read().decode("utf-8")
            return json.loads(body)
    except urllib.error.HTTPError as exc:
        fail(f"API request failed: {url} -> HTTP {exc.code}")
    except urllib.error.URLError as exc:
        fail(f"API request failed: {url} -> {exc}")
    except json.JSONDecodeError as exc:
        fail(f"API response is not valid JSON for {url}: {exc}")


def resolve(query: dict[str, Any]) -> dict[str, str]:
    api_url = str(query.get("api_url", "")).strip()
    api_token = str(query.get("api_token", "")).strip()
    endpoint_template = str(query.get("endpoint_template", "")).strip()
    server_id = str(query.get("server_id", "")).strip()
    auth_header = str(query.get("auth_header", "Authorization")).strip()
    auth_scheme = str(query.get("auth_scheme", "Bearer")).strip()

    if not api_url:
        fail("api_url is required")
    if not endpoint_template:
        fail("endpoint_template is required")
    if not server_id:
        fail("server_id is required")
    if not api_token:
        fail("api_token is required")

    endpoint = endpoint_template.replace("{server_id}", server_id)
    url = f"{api_url.rstrip('/')}/{endpoint.lstrip('/')}"

    auth_value = f"{auth_scheme} {api_token}".strip() if auth_scheme else api_token
    headers = {"Accept": "application/json"}
    if auth_header:
        headers[auth_header] = auth_value

    payload = get_json(url, headers)
    ips = find_ips(payload)
    public_ips = [ip for ip in ips if is_public_ipv4(ip)]
    chosen_ip = public_ips[0] if public_ips else (ips[0] if ips else "")
    if not chosen_ip:
        fail(f"Could not extract IPv4 address from response: {url}")

    return {"public_ip": chosen_ip, "region": find_region(payload)}


def main() -> None:
    try:
        query = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        fail(f"Invalid external query JSON: {exc}")
    print(json.dumps(resolve(query)))


if __name__ == "__main__":
    main()
