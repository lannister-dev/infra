from __future__ import annotations

import logging
import sys
from pathlib import Path
from typing import Any

from scripts.profiles.core.builder import ArtifactBuilder
from scripts.profiles.core.constants import (
    ARTIFACT_OUTPUT_DEFAULT,
    XRAY_OVERRIDES_DEFAULT,
    XRAY_TEMPLATE_DEFAULT,
)
from scripts.profiles.core.errors import ArtifactBuildError

log = logging.getLogger("profiles.xray_artifact")


def setup_logging(verbose: bool = False) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        format="%(levelname)s %(name)s: %(message)s",
        level=level,
        stream=sys.stderr,
    )


def build_artifact(
    *,
    template_path: Path = XRAY_TEMPLATE_DEFAULT,
    overrides_path: Path = XRAY_OVERRIDES_DEFAULT,
    strict: bool = True,
) -> dict[str, dict[str, Any]]:
    builder = ArtifactBuilder(strict=strict)
    return builder.build_artifact(template_path=template_path, overrides_path=overrides_path)


__all__ = [
    "ARTIFACT_OUTPUT_DEFAULT",
    "XRAY_OVERRIDES_DEFAULT",
    "XRAY_TEMPLATE_DEFAULT",
    "ArtifactBuildError",
    "build_artifact",
    "setup_logging",
]
