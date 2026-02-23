#!/usr/bin/env python3
"""Generate profiles artifact from Xray template and optionally publish it."""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

from environs import Env

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from services.profiles.api import ControlPlaneClient
from services.profiles.artifact.builder import ArtifactBuilder
from services.profiles.artifact.constants import (
    ARTIFACT_OUTPUT_DEFAULT,
    XRAY_OVERRIDES_DEFAULT,
    XRAY_TEMPLATE_DEFAULT,
)
from services.profiles.artifact.errors import ArtifactBuildError, ArtifactPublishError
from services.profiles.artifact.publisher import ArtifactPublisher

log = logging.getLogger("profiles.artifact")


def _setup_logging(verbose: bool = False) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        format="%(levelname)s %(name)s: %(message)s",
        level=level,
        stream=sys.stderr,
    )


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

    _setup_logging(args.verbose)

    try:
        artifact = ArtifactBuilder(strict=not args.non_strict).build_artifact(
            template_path=args.xray_template,
            overrides_path=args.overrides,
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
        env = Env()
        env.read_env(".env")
        base_url = env.str("CONTROL_PLANE_URL")
        api_key = env.str("ADMIN_API_KEY")

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
