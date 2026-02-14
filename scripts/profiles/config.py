from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache

from environs import Env


@dataclass(frozen=True)
class ControlPlaneConfig:
    url: str | None
    admin_api_key: str | None


@dataclass(frozen=True)
class Settings:
    control_plane: ControlPlaneConfig


def _normalize(value: str) -> str | None:
    normalized = value.strip()
    return normalized or None


@lru_cache
def get_settings() -> Settings:
    env = Env()
    env.read_env(".env")

    control_plane = ControlPlaneConfig(
        url=_normalize(env.str("CONTROL_PLANE_URL", default="")),
        admin_api_key=_normalize(env.str("ADMIN_API_KEY", default="")),
    )

    return Settings(control_plane=control_plane)


settings = get_settings()


__all__ = ["ControlPlaneConfig", "Settings", "get_settings", "settings"]
