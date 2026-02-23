"""Common API error hierarchy."""


class HttpError(RuntimeError):
    """Raw HTTP error with status and body."""

    def __init__(self, status: int, body: str) -> None:
        super().__init__(f"HTTP {status}: {body}")
        self.status = status
        self.body = body


class ApiError(Exception):
    """Base error for API clients."""


class RetryableApiError(ApiError):
    """Transient error: network / timeouts / 5xx."""


class NonRetryableApiError(ApiError):
    """Permanent error: 4xx / auth / schema mismatch."""

