"""
Base synchronous HTTP client.

Mirrors node-agent's BaseApiClient pattern but uses urllib
(no external deps beyond stdlib).
"""
from __future__ import annotations

import json
import logging
import urllib.error
import urllib.request
from typing import Any

from .exceptions import HttpError

log = logging.getLogger("profiles.api")


class BaseApiClient:
    def __init__(
        self,
        *,
        base_url: str,
        headers: dict[str, str] | None = None,
        timeout_s: float = 10,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._headers = headers or {}
        self._timeout = timeout_s

    def _request(self, method: str, path: str, *, body: dict[str, Any] | None = None) -> Any:
        if not path.startswith("/"):
            raise ValueError("path must start with '/'")

        url = f"{self._base_url}{path}"
        data = json.dumps(body).encode("utf-8") if body is not None else None
        headers = {"Accept": "application/json", **self._headers}
        if data is not None:
            headers["Content-Type"] = "application/json"

        req = urllib.request.Request(url, data=data, headers=headers, method=method)

        log.debug("%s %s", method, url)
        try:
            with urllib.request.urlopen(req, timeout=self._timeout) as resp:
                text = resp.read().decode("utf-8", errors="replace")
                if not text:
                    return None

                try:
                    return json.loads(text)
                except json.JSONDecodeError:
                    return text

        except urllib.error.HTTPError as exc:
            body_text = exc.read().decode("utf-8", errors="replace")
            raise HttpError(exc.code, body_text) from exc
        except urllib.error.URLError as exc:
            raise HttpError(0, str(exc.reason)) from exc

    def get(self, path: str) -> Any:
        return self._request("GET", path)

    def post(self, path: str, *, body: dict[str, Any] | None = None) -> Any:
        return self._request("POST", path, body=body)

    def put(self, path: str, *, body: dict[str, Any] | None = None) -> Any:
        return self._request("PUT", path, body=body)
