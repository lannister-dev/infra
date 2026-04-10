#!/usr/bin/env python3
"""Render per-reference SSH private keys from ANSIBLE_SSH_KEYS_B64_JSON."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys


REF_RE = re.compile(r"^[A-Za-z0-9._-]+$")


def _fail(message: str) -> int:
    print(f"::error::{message}", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--keys-dir", required=True)
    args = parser.parse_args()

    raw = os.environ.get("ANSIBLE_SSH_KEYS_B64_JSON", "").strip()
    if raw == "":
        print("0")
        return 0

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        return _fail(f"ANSIBLE_SSH_KEYS_B64_JSON is not valid JSON: {exc}")

    if not isinstance(payload, dict):
        return _fail('ANSIBLE_SSH_KEYS_B64_JSON must be a JSON object: {"ref":"base64_key"}')

    count = 0
    for ref, encoded_key in payload.items():
        if not isinstance(ref, str) or not REF_RE.match(ref):
            return _fail(f"Invalid ssh key ref '{ref}'. Allowed pattern: [A-Za-z0-9._-]+")
        if not isinstance(encoded_key, str) or encoded_key.strip() == "":
            return _fail(f"SSH key value for ref '{ref}' must be non-empty base64 string")

        encoded_key = "".join(encoded_key.split())
        if encoded_key.endswith("%"):
            return _fail(
                f"SSH key ref '{ref}' ends with '%'. Remove shell prompt artifacts and keep only raw base64 text."
            )

        try:
            key_bytes = base64.b64decode(encoded_key, validate=True)
        except Exception as exc:  # noqa: BLE001 - preserve actionable error text
            return _fail(f"Failed to decode base64 for ssh key ref '{ref}': {exc}")

        key_path = os.path.join(args.keys_dir, ref)
        with open(key_path, "wb") as fh:
            fh.write(key_bytes)
        os.chmod(key_path, 0o600)
        count += 1

    print(str(count))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
