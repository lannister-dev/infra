"""Base async HTTP client using aiohttp."""

from __future__ import annotations

import logging
from typing import Any

import aiohttp
from aiohttp import ClientTimeout

from .exceptions import HttpError

log = logging.getLogger("shared.api")


class BaseApiClient:
    def __init__(
        self,
        *,
        base_url: str,
        headers: dict[str, str],
        timeout_s: float,
    ):
        self._base_url = base_url
        self._headers = headers
        self._timeout = ClientTimeout(total=timeout_s)
        self._session: aiohttp.ClientSession | None = None

    async def _get_session(self) -> aiohttp.ClientSession:
        if self._session is None:
            self._session = aiohttp.ClientSession(
                headers=self._headers,
                timeout=self._timeout,
            )
        return self._session

    async def close(self) -> None:
        if self._session:
            await self._session.close()
            self._session = None

    async def update_headers(self, headers: dict[str, str]) -> None:
        self._headers = headers
        if self._session:
            await self._session.close()
            self._session = None

    async def get(self, path: str, *, params: dict[str, Any] | None = None) -> Any:
        session = await self._get_session()
        async with session.get(f"{self._base_url}{path}", params=params) as response:
            if response.status >= 400:
                raise HttpError(response.status, await response.text())
            return await response.json()

    async def post(
        self,
        path: str,
        *,
        json: dict[str, Any] | None = None,
        params: dict[str, Any] | None = None,
    ) -> Any:
        session = await self._get_session()
        async with session.post(f"{self._base_url}{path}", json=json, params=params) as response:
            if response.status >= 400:
                raise HttpError(response.status, await response.text())
            text = await response.text()
            if not text:
                return None
            return await response.json()
