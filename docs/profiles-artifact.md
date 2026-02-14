# Profiles Artifact Pipeline

## Source of truth

Profiles artifact is generated from:

- `vpn/xray/config.json.j2` (Xray inbounds)
- `vpn/xray/artifact.overrides.yml` (prod mapping/overrides)
- `vpn/xray/artifact.overrides.dev.yml` (dev mapping/overrides)

`config.json.j2` is the canonical source for server transport configuration.

## Why overrides are required

Some client-facing fields are not always derivable from raw Xray inbound config:

- profile key naming (`ws_tls_v1`, `reality_tcp_v1`, ...)
- `display_name`
- `reality_tcp.client.public_key` and other client policy fields

`artifact.overrides.yml` exists to provide these values in a controlled way.

## Local commands

From repository root:

```bash
python -m scripts.profiles.validate_profiles
python -m scripts.profiles.generate_profiles_artifact --print
python -m scripts.profiles.generate_profiles_artifact --publish
```

Useful publish controls:

```bash
python -m scripts.profiles.generate_profiles_artifact --publish --max-attempts 5 --base-delay-s 2.0 --timeout-s 15
```

By default, generated payload is written to:

- `artifacts/profiles/artifact.json`

Payload shape matches Control Plane contract:

```json
{
  "artifact": {
    "ws_tls_v1": {
      "type": "ws_tls",
      "display_name": "CDN WS TLS",
      "client": {
        "path": "/api/v1/stream",
        "host": "tech.lannister-dev.ru",
        "sni": "tech.lannister-dev.ru"
      }
    }
  }
}
```

## CI behavior

Workflows:

- `.github/workflows/profiles.yml` (prod artifact pipeline)
- `.github/workflows/profiles-dev.yml` (dev artifact pipeline)

Pipeline stages:

1. Prod workflow validates/builds `artifact.overrides.yml` and publishes via `CONTROL_PLANE_URL` + `ADMIN_API_KEY`.
2. Dev workflow validates/builds `artifact.overrides.dev.yml` and publishes via `CONTROL_PLANE_URL_DEV` + `ADMIN_API_KEY_DEV`.
3. Dev publish is skipped when dev secrets are not configured.

`CONTROL_PLANE_URL` should point to the artifacts API base, for example:

- `https://api.lannister-dev.ru/api/v1/artifacts`

Dev publish expects separate secrets:

- `CONTROL_PLANE_URL_DEV`
- `ADMIN_API_KEY_DEV`

## Why these workflows exist

`profiles.yml` and `profiles-dev.yml` are dedicated CI/CD workflows for profile artifacts. They isolate profile validation/publish from infra deploy and separate prod/dev overrides, endpoints, and secrets.

## Module architecture

Core logic lives in `scripts/profiles/core/`:

- `builder.py` — typed artifact builder from template + overrides.
- `models.py` — pydantic domain models and contract validation.
- `template.py` — safe template rendering and placeholder detection.
- `publish.py` — publish/reload orchestration with retry policy.

CLI entrypoints (`validate_profiles.py`, `generate_profiles_artifact.py`) are thin wrappers over this core.

## Dependencies

Requirements are split by concern:

- `requirements/base.txt` — base runtime stack.
- `requirements/dev.txt` — base + test/tooling (`pytest`, `ruff`, `mypy`).

Default `requirements.txt` installs `requirements/dev.txt`.
