#!/usr/bin/env python3
"""Verify that local SSH keys match HostVDS/OpenStack keypair fingerprints."""

from __future__ import annotations

import argparse
import subprocess
import sys
import urllib.parse
from os import environ

from services.providers.resolvers.hostvds_openstack import (
    build_keystone_auth_payload,
    find_compute_endpoints,
    request_json,
)


def _fail(message: str) -> int:
    print(f"::error::{message}", file=sys.stderr)
    return 1


def _required_env(name: str) -> str:
    value = environ.get(name, "").strip()
    if value == "":
        raise ValueError(name)
    return value


def _normalize_md5_fingerprint(raw: str) -> str:
    value = raw.strip().lower()
    if value.startswith("md5:"):
        value = value[4:]
    return value


def _local_key_fingerprint_md5(private_key_path: str) -> str:
    pub = subprocess.run(
        ["ssh-keygen", "-y", "-f", private_key_path],
        check=True,
        text=True,
        capture_output=True,
    ).stdout
    fp_line = subprocess.run(
        ["ssh-keygen", "-lf", "-", "-E", "md5"],
        input=pub,
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()

    parts = fp_line.split()
    if len(parts) < 2:
        raise RuntimeError(f"Unexpected ssh-keygen fingerprint output: '{fp_line}'")
    return _normalize_md5_fingerprint(parts[1])


def _keystone_token_and_catalog(
    os_auth_url: str,
    os_username: str,
    os_password: str,
    os_project_name: str,
    os_user_domain_name: str,
    os_user_domain_id: str,
    os_project_domain_name: str,
    os_project_domain_id: str,
) -> tuple[str, list[dict]]:
    normalized_query = {
        "os_username": os_username,
        "os_password": os_password,
        "os_project_name": os_project_name,
        "os_user_domain_name": os_user_domain_name,
        "os_user_domain_id": os_user_domain_id,
        "os_project_domain_name": os_project_domain_name,
        "os_project_domain_id": os_project_domain_id,
    }

    auth_base = os_auth_url.rstrip("/")
    keystone_candidates = [f"{auth_base}/auth/tokens"]
    if not auth_base.endswith("/v3") and not auth_base.endswith("v3"):
        keystone_candidates.insert(0, f"{auth_base}/v3/auth/tokens")

    auth_payload = build_keystone_auth_payload(normalized_query)
    auth_response = None
    auth_headers: dict[str, str] = {}
    auth_errors: list[str] = []

    for keystone_url in keystone_candidates:
        auth_response, auth_headers = request_json(
            "POST",
            keystone_url,
            {"Accept": "application/json"},
            auth_payload,
            fatal=False,
        )
        if auth_response is not None:
            break
        auth_errors.append(f"{keystone_url}: {auth_headers.get('__error__', 'unknown error')}")

    if auth_response is None:
        raise RuntimeError("Keystone auth failed: " + "; ".join(auth_errors))

    token = auth_headers.get("X-Subject-Token") or auth_headers.get("x-subject-token")
    if not token:
        raise RuntimeError("Keystone auth succeeded but token header is missing")

    catalog = auth_response.get("token", {}).get("catalog", [])
    if not isinstance(catalog, list):
        raise RuntimeError("Invalid Keystone catalog in auth response")
    return token, catalog


def _fetch_remote_keypair_fingerprint_md5(
    *,
    token: str,
    catalog: list[dict],
    interface: str,
    preferred_region: str,
    keypair_name: str,
) -> str:
    endpoints = find_compute_endpoints(catalog, interface, preferred_region)
    lookup_errors: list[str] = []

    for compute_base_url, _region in endpoints:
        keypair_url = (
            f"{compute_base_url.rstrip('/')}/os-keypairs/"
            f"{urllib.parse.quote(keypair_name, safe='')}"
        )
        payload, error_headers = request_json(
            "GET",
            keypair_url,
            {"Accept": "application/json", "X-Auth-Token": token},
            fatal=False,
        )
        if payload is None:
            lookup_errors.append(
                f"{keypair_url}: {error_headers.get('__error__', 'unknown error')}"
            )
            continue

        keypair = payload.get("keypair", {})
        raw_fp = str(keypair.get("fingerprint", "")).strip()
        if raw_fp == "":
            raise RuntimeError(
                f"Keypair '{keypair_name}' found but fingerprint is empty in API response"
            )
        return _normalize_md5_fingerprint(raw_fp)

    raise RuntimeError(
        f"Could not resolve keypair '{keypair_name}' in compute API endpoints: "
        + "; ".join(lookup_errors)
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--keys-dir", required=True)
    parser.add_argument(
        "--refs",
        required=True,
        help="Comma-separated key refs to verify (expected keypair names in HostVDS/OpenStack)",
    )
    args = parser.parse_args()

    key_refs = [ref.strip() for ref in args.refs.split(",") if ref.strip() != ""]
    if not key_refs:
        print("::notice::No key refs provided for HostVDS keypair verification")
        return 0

    try:
        os_auth_url = _required_env("HOSTVDS_OS_AUTH_URL")
        os_username = _required_env("HOSTVDS_OS_USERNAME")
        os_password = _required_env("HOSTVDS_OS_PASSWORD")
        os_project_name = _required_env("HOSTVDS_OS_PROJECT_NAME")
        os_interface = _required_env("HOSTVDS_OS_INTERFACE")
    except ValueError as exc:
        return _fail(
            f"Missing required HostVDS/OpenStack env for keypair verification: {exc.args[0]}"
        )

    os_user_domain_name = environ.get("HOSTVDS_OS_USER_DOMAIN_NAME", "").strip()
    os_user_domain_id = environ.get("HOSTVDS_OS_USER_DOMAIN_ID", "").strip()
    os_project_domain_name = environ.get("HOSTVDS_OS_PROJECT_DOMAIN_NAME", "").strip()
    os_project_domain_id = environ.get("HOSTVDS_OS_PROJECT_DOMAIN_ID", "").strip()
    os_region_name = environ.get("HOSTVDS_OS_REGION_NAME", "").strip()

    if os_user_domain_name == "" and os_user_domain_id == "":
        return _fail(
            "Set HOSTVDS_OS_USER_DOMAIN_NAME or HOSTVDS_OS_USER_DOMAIN_ID for keypair verification"
        )
    if os_project_domain_name == "" and os_project_domain_id == "":
        return _fail(
            "Set HOSTVDS_OS_PROJECT_DOMAIN_NAME or HOSTVDS_OS_PROJECT_DOMAIN_ID for keypair verification"
        )

    try:
        token, catalog = _keystone_token_and_catalog(
            os_auth_url=os_auth_url,
            os_username=os_username,
            os_password=os_password,
            os_project_name=os_project_name,
            os_user_domain_name=os_user_domain_name,
            os_user_domain_id=os_user_domain_id,
            os_project_domain_name=os_project_domain_name,
            os_project_domain_id=os_project_domain_id,
        )
    except Exception as exc:  # noqa: BLE001
        return _fail(f"Failed to authenticate in HostVDS/OpenStack for keypair check: {exc}")

    mismatches: list[str] = []
    for key_ref in key_refs:
        private_key_path = f"{args.keys_dir.rstrip('/')}/{key_ref}"
        try:
            local_fp = _local_key_fingerprint_md5(private_key_path)
        except Exception as exc:  # noqa: BLE001
            return _fail(
                f"Failed to derive local fingerprint for key ref '{key_ref}' at "
                f"'{private_key_path}': {exc}"
            )

        try:
            remote_fp = _fetch_remote_keypair_fingerprint_md5(
                token=token,
                catalog=catalog,
                interface=os_interface,
                preferred_region=os_region_name,
                keypair_name=key_ref,
            )
        except Exception as exc:  # noqa: BLE001
            return _fail(f"Failed to fetch HostVDS keypair '{key_ref}' fingerprint: {exc}")

        if local_fp == remote_fp:
            print(
                f"::notice::SSH key ref '{key_ref}' matches HostVDS keypair fingerprint "
                f"(md5={local_fp})"
            )
            continue

        mismatches.append(
            f"ref={key_ref} local_md5={local_fp} hostvds_keypair_md5={remote_fp}"
        )

    if mismatches:
        return _fail("HostVDS keypair fingerprint mismatch: " + "; ".join(mismatches))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
