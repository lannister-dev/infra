#!/usr/bin/env python3
"""Validate generated artifact payload against control-plane schema."""
from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.profiles.api.schemas import ProfileArtifactPublishIn
from scripts.profiles.xray_artifact import (
    XRAY_OVERRIDES_DEFAULT,
    XRAY_TEMPLATE_DEFAULT,
    ArtifactBuildError,
    build_artifact,
    setup_logging,
)

log = logging.getLogger("profiles.validate")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate profiles artifact generated from xray template"
    )
    parser.add_argument("--xray-template", type=Path, default=XRAY_TEMPLATE_DEFAULT)
    parser.add_argument("--overrides", type=Path, default=XRAY_OVERRIDES_DEFAULT)
    parser.add_argument("--non-strict", action="store_true")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    setup_logging(args.verbose)

    if not args.xray_template.exists():
        log.error("File not found: %s", args.xray_template)
        sys.exit(1)

    try:
        artifact = build_artifact(
            template_path=args.xray_template,
            overrides_path=args.overrides,
            strict=not args.non_strict,
        )
        payload = ProfileArtifactPublishIn.model_validate({"artifact": artifact})
    except ArtifactBuildError as exc:
        log.error("FAILED - %s", exc)
        sys.exit(1)
    except Exception as exc:
        log.error("FAILED - schema validation error: %s", exc)
        sys.exit(1)

    log.info("OK - artifact is valid (%d profile(s))", len(payload.artifact))
    for key, profile in payload.artifact.items():
        log.info("  %s (%s): %s", key, profile.type, profile.display_name)


if __name__ == "__main__":
    main()
