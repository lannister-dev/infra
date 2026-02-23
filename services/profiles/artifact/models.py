from __future__ import annotations

from typing import Annotated, Any, Literal, TypeAlias

from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, field_validator

ProfileType: TypeAlias = Literal["ws_tls", "reality_tcp"]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class WsTlsClient(StrictModel):
    path: str = Field(..., min_length=1, max_length=256)
    host: str = Field(..., min_length=1, max_length=255)
    sni: str = Field(..., min_length=1, max_length=255)

    @field_validator("path")
    @classmethod
    def validate_path(cls, value: str) -> str:
        if not value.startswith("/"):
            value = "/" + value
        return value


class WsTlsProfile(StrictModel):
    type: Literal["ws_tls"] = "ws_tls"
    display_name: str = Field(..., min_length=1)
    client: WsTlsClient


class RealityTcpClient(StrictModel):
    sni: str = Field(..., min_length=1, max_length=255)
    flow: str | None = Field(default=None, min_length=1, max_length=64)
    fingerprint: str = Field(..., min_length=1, max_length=64)
    public_key: str = Field(..., min_length=16, max_length=128)
    short_id: str = Field(..., min_length=1, max_length=32)
    spider_x: str | None = Field(default=None, max_length=128)

    @field_validator("flow", mode="before")
    @classmethod
    def normalize_flow(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if isinstance(value, str) and not value.strip():
            return None
        return value


class RealityTcpProfile(StrictModel):
    type: Literal["reality_tcp"] = "reality_tcp"
    display_name: str = Field(..., min_length=1)
    client: RealityTcpClient


ArtifactProfile = Annotated[WsTlsProfile | RealityTcpProfile, Field(discriminator="type")]


class ArtifactPayload(StrictModel):
    artifact: dict[str, ArtifactProfile] = Field(..., min_length=1)

    @field_validator("artifact")
    @classmethod
    def validate_artifact_keys(
        cls,
        value: dict[str, ArtifactProfile],
    ) -> dict[str, ArtifactProfile]:
        for key in value:
            if not key.strip():
                raise ValueError("artifact profile key must not be empty")
        return value


class WsTlsClientOverride(StrictModel):
    path: str | None = None
    host: str | None = None
    sni: str | None = None

    @field_validator("path")
    @classmethod
    def validate_path(cls, value: str | None) -> str | None:
        if value is not None and not value.startswith("/"):
            raise ValueError("path must start with '/'")
        return value


class RealityTcpClientOverride(StrictModel):
    sni: str | None = None
    flow: str | None = None
    fingerprint: str | None = None
    public_key: str | None = None
    short_id: str | None = Field(default=None, max_length=32)
    spider_x: str | None = Field(default=None, max_length=128)

    @field_validator("flow", mode="before")
    @classmethod
    def normalize_flow(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if isinstance(value, str) and not value.strip():
            return None
        return value


class ProfileOverride(StrictModel):
    enabled: bool = True
    key: str | None = None
    type: ProfileType | None = None
    display_name: str | None = None
    client: dict[str, Any] | None = None

    @field_validator("key", "display_name")
    @classmethod
    def non_empty_if_present(cls, value: str | None) -> str | None:
        if value is not None and not value.strip():
            raise ValueError("value must not be empty")
        return value


_OVERRIDES_ADAPTER = TypeAdapter(dict[str, ProfileOverride])
_WS_CLIENT_OVERRIDE_ADAPTER = TypeAdapter(WsTlsClientOverride)
_REALITY_CLIENT_OVERRIDE_ADAPTER = TypeAdapter(RealityTcpClientOverride)


def parse_overrides_map(raw: Any) -> dict[str, ProfileOverride]:
    """Parse validated overrides map keyed by inbound tag."""

    return _OVERRIDES_ADAPTER.validate_python(raw)


def parse_client_override(
    *,
    profile_type: ProfileType,
    raw_client_override: dict[str, Any] | None,
) -> WsTlsClientOverride | RealityTcpClientOverride | None:
    """Parse type-specific client override block."""

    if raw_client_override is None:
        return None

    if profile_type == "ws_tls":
        return _WS_CLIENT_OVERRIDE_ADAPTER.validate_python(raw_client_override)

    return _REALITY_CLIENT_OVERRIDE_ADAPTER.validate_python(raw_client_override)


def artifact_to_dict(artifact: dict[str, ArtifactProfile]) -> dict[str, dict[str, Any]]:
    """Convert typed artifact to plain dict for JSON serialization."""

    return {
        key: profile.model_dump(mode="json", exclude_none=True)
        for key, profile in artifact.items()
    }


__all__ = [
    "ArtifactPayload",
    "ArtifactProfile",
    "ProfileOverride",
    "ProfileType",
    "RealityTcpClient",
    "RealityTcpClientOverride",
    "RealityTcpProfile",
    "WsTlsClient",
    "WsTlsClientOverride",
    "WsTlsProfile",
    "artifact_to_dict",
    "parse_client_override",
    "parse_overrides_map",
]
