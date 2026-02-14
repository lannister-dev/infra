#!/usr/bin/env python3
"""Generate profiles artifact from Xray template and optionally publish it."""
from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from pathlib import Path

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.profiles.api import ControlPlaneClient
from scripts.profiles.core.errors import ArtifactPublishError
from scripts.profiles.core.publish import ArtifactPublisher
from scripts.profiles.xray_artifact import (
    ARTIFACT_OUTPUT_DEFAULT,
    XRAY_OVERRIDES_DEFAULT,
    XRAY_TEMPLATE_DEFAULT,
    ArtifactBuildError,
    build_artifact,
    setup_logging,
)

log = logging.getLogger("profiles.artifact")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate profiles artifact for control plane from vpn/xray/config.json.j2"
    )
    parser.add_argument("--xray-template", type=Path, default=XRAY_TEMPLATE_DEFAULT)
    parser.add_argument("--overrides", type=Path, default=XRAY_OVERRIDES_DEFAULT)
    parser.add_argument("--output", type=Path, default=ARTIFACT_OUTPUT_DEFAULT)
    parser.add_argument("--publish", action="store_true")
    parser.add_argument("--skip-reload", action="store_true")
    parser.add_argument("--non-strict", action="store_true")
    parser.add_argument("--max-attempts", type=int, default=4)
    parser.add_argument("--base-delay-s", type=float, default=1.5)
    parser.add_argument("--timeout-s", type=float, default=10.0)
    parser.add_argument("--print", action="store_true", dest="print_payload")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    setup_logging(args.verbose)

    try:
        artifact = build_artifact(
            template_path=args.xray_template,
            overrides_path=args.overrides,
            strict=not args.non_strict,
        )
    except ArtifactBuildError as exc:
        log.error("%s", exc)
        sys.exit(1)

    payload = {"artifact": artifact}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    log.info("Artifact written to %s (%d profile(s))", args.output, len(artifact))

    if args.publish:
        base_url = os.environ.get("CONTROL_PLANE_URL")
        api_key = os.environ.get("ADMIN_API_KEY")
        if not base_url or not api_key:
            log.error("CONTROL_PLANE_URL and ADMIN_API_KEY env vars required for --publish")
            sys.exit(1)

        client = ControlPlaneClient(base_url=base_url, api_key=api_key, timeout_s=args.timeout_s)
        publisher = ArtifactPublisher(
            client=client,
            max_attempts=args.max_attempts,
            base_delay_s=args.base_delay_s,
        )

        try:
            publisher.publish(artifact, reload_registry=not args.skip_reload)
        except (ArtifactPublishError, ValueError) as exc:
            log.error("%s", exc)
            sys.exit(1)

    if args.print_payload:
        print(json.dumps(payload, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
