from __future__ import annotations

import asyncio
import logging
from typing import Any

from shared.api import BaseApiClient
from shared.api.exceptions import HttpError, NonRetryableApiError, RetryableApiError

from .schemas import PublishArtifactResponse, ReloadStatusResponse

log = logging.getLogger("profiles.api")


class ControlPlaneClient(BaseApiClient):
    def __init__(self, *, base_url: str, api_key: str, timeout_s: float = 10):
        super().__init__(
            base_url=base_url,
            headers={"Authorization": f"Bearer {api_key}"},
            timeout_s=timeout_s,
        )

    @staticmethod
    def _classify_error(exc: HttpError) -> RetryableApiError | NonRetryableApiError:
        if exc.status >= 500 or exc.status in {0, 408, 429}:
            return RetryableApiError(str(exc))
        return NonRetryableApiError(str(exc))

    async def _post_once(
        self,
        path: str,
        *,
        json_payload: dict[str, Any] | None = None,
    ) -> Any:
        """Run one POST call and close aiohttp session in the same event loop."""
        try:
            return await self.post(path, json=json_payload)
        finally:
            await self.close()

    def publish_artifact(self, artifact: dict[str, Any]) -> dict[str, Any]:
        try:
            result = asyncio.run(
                self._post_once(
                    "/profiles/publish",
                    json_payload={"artifact": artifact},
                )
            )
            if not isinstance(result, dict):
                raise NonRetryableApiError(
                    f"Publish returned non-JSON object response: {type(result).__name__}"
                )

            payload = PublishArtifactResponse.model_validate(result)
            log.info(
                "Published artifact: version=%s checksum=%s",
                payload.version,
                payload.checksum,
            )
            return payload.model_dump(mode="json", exclude_none=True)

        except HttpError as exc:
            log.error("Publish failed (%d): %s", exc.status, exc.body)
            raise self._classify_error(exc) from exc

    def reload_registry(self) -> dict[str, Any]:
        """Trigger registry reload after publish."""
        try:
            result = asyncio.run(self._post_once("/profiles/reload"))
            if not isinstance(result, dict):
                raise NonRetryableApiError(
                    f"Reload returned non-JSON object response: {type(result).__name__}"
                )

            payload = ReloadStatusResponse.model_validate(result)
            log.info("Registry reloaded: %s", payload.status)
            return payload.model_dump(mode="json")

        except HttpError as exc:
            log.error("Reload failed (%d): %s", exc.status, exc.body)
            raise self._classify_error(exc) from exc
