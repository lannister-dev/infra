"""Domain-specific errors for profiles artifact pipeline."""

from __future__ import annotations


class ProfilesError(RuntimeError):
    """Base error for profiles pipeline."""


class ArtifactBuildError(ProfilesError):
    """Raised when xray template cannot be converted into a valid artifact."""


class ArtifactPublishError(ProfilesError):
    """Raised when artifact publish cannot be completed."""
