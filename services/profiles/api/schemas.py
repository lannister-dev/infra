from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from services.profiles.artifact.models import (
    ArtifactPayload,
    RealityTcpProfile,
    WsTlsProfile,
)


class ProfileArtifactPublishIn(ArtifactPayload):
    """Incoming publish payload validated against supported profile types."""


class ProfileArtifactCreate(BaseModel):
    version: int
    artifact: dict[str, WsTlsProfile | RealityTcpProfile]
    checksum: str


class ProfileArtifactUpdate(BaseModel):
    is_active: bool | None = None


class ProfileArtifactOut(BaseModel):
    id: UUID
    version: int
    checksum: str
    artifact: dict[str, WsTlsProfile | RealityTcpProfile]
    is_active: bool
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class PublishArtifactResponse(BaseModel):
    version: int
    checksum: str
    artifact: dict[str, Any] | None = None


class ReloadStatusResponse(BaseModel):
    status: str


class ErrorResponse(BaseModel):
    detail: str
