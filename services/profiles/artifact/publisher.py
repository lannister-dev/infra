from __future__ import annotations

import logging
import time
from typing import Any

from services.profiles.api.client import ControlPlaneClient
from shared.api.exceptions import NonRetryableApiError, RetryableApiError

from .errors import ArtifactPublishError

log = logging.getLogger("profiles.publisher")


class ArtifactPublisher:
    """Publish artifact to control plane with retry policy."""

    def __init__(
        self,
        *,
        client: ControlPlaneClient,
        max_attempts: int = 4,
        base_delay_s: float = 1.5,
    ) -> None:
        if max_attempts < 1:
            raise ValueError("max_attempts must be >= 1")
        if base_delay_s <= 0:
            raise ValueError("base_delay_s must be > 0")

        self._client = client
        self._max_attempts = max_attempts
        self._base_delay_s = base_delay_s

    def publish(self, artifact: dict[str, Any], *, reload_registry: bool = True) -> dict[str, Any]:
        response: dict[str, Any] | None = None

        for attempt in range(1, self._max_attempts + 1):
            try:
                response = self._client.publish_artifact(artifact)
                break
            except RetryableApiError as exc:
                if attempt == self._max_attempts:
                    raise ArtifactPublishError(
                        f"publish failed after {self._max_attempts} attempts: {exc}"
                    ) from exc

                delay_s = self._base_delay_s * (2 ** (attempt - 1))
                log.warning(
                    "Publish attempt %d/%d failed with retryable error: %s. Retrying in %.1fs",
                    attempt,
                    self._max_attempts,
                    exc,
                    delay_s,
                )
                time.sleep(delay_s)
            except NonRetryableApiError as exc:
                raise ArtifactPublishError(f"publish failed permanently: {exc}") from exc

        if response is None:
            raise ArtifactPublishError("publish did not return response")

        if reload_registry:
            try:
                self._client.reload_registry()
            except RetryableApiError as exc:
                raise ArtifactPublishError(f"reload failed with retryable error: {exc}") from exc
            except NonRetryableApiError as exc:
                raise ArtifactPublishError(f"reload failed permanently: {exc}") from exc

        return response


__all__ = ["ArtifactPublisher"]
