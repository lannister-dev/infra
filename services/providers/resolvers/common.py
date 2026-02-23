from __future__ import annotations

import ipaddress
import re
from typing import Any


def is_ipv4(value: str) -> bool:
    try:
        ip = ipaddress.ip_address(value)
    except ValueError:
        return False
    return isinstance(ip, ipaddress.IPv4Address)


def is_public_ipv4(value: str) -> bool:
    if not is_ipv4(value):
        return False
    ip = ipaddress.ip_address(value)
    return not (
        ip.is_private
        or ip.is_loopback
        or ip.is_link_local
        or ip.is_multicast
        or ip.is_reserved
    )


def find_ips(obj: Any) -> list[str]:
    found: list[str] = []
    if isinstance(obj, dict):
        for value in obj.values():
            found.extend(find_ips(value))
    elif isinstance(obj, list):
        for value in obj:
            found.extend(find_ips(value))
    elif isinstance(obj, str):
        if is_ipv4(obj):
            found.append(obj)
        else:
            for token in re.findall(r"(?:\d{1,3}\.){3}\d{1,3}", obj):
                if is_ipv4(token):
                    found.append(token)
    return found


def find_region(obj: Any) -> str:
    if isinstance(obj, dict):
        preferred_keys = ("region", "location", "datacenter", "dc", "zone")
        for key in preferred_keys:
            if key in obj and isinstance(obj[key], str) and obj[key].strip():
                return obj[key].strip()
        for value in obj.values():
            candidate = find_region(value)
            if candidate:
                return candidate
    elif isinstance(obj, list):
        for value in obj:
            candidate = find_region(value)
            if candidate:
                return candidate
    return ""
