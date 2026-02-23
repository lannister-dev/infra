"""Shared synchronous HTTP API client primitives."""

from .base_client import BaseApiClient
from .exceptions import ApiError, HttpError, NonRetryableApiError, RetryableApiError

__all__ = [
    "BaseApiClient",
    "HttpError",
    "ApiError",
    "RetryableApiError",
    "NonRetryableApiError",
]

