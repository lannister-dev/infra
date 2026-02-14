from __future__ import annotations

import logging
from typing import Any

from .base_client import BaseApiClient
from .exceptions import HttpError, NonRetryableApiError, RetryableApiError
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

    def publish_artifact(self, artifact: dict[str, Any]) -> dict[str, Any]:
        try:
            result = self.post(
                "/api/v1/artifacts/profiles/publish",
                body={"artifact": artifact},
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
            result = self.post("/api/v1/artifacts/profiles/reload")
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
