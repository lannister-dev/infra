from __future__ import annotations

import importlib
import logging
import re
from pathlib import Path
from typing import Any

from pydantic import ValidationError

from .constants import SUPPORTED_PROFILE_TYPES, XRAY_OVERRIDES_DEFAULT, XRAY_TEMPLATE_DEFAULT
from .errors import ArtifactBuildError
from .models import (
    ArtifactPayload,
    ProfileOverride,
    RealityTcpClient,
    RealityTcpClientOverride,
    RealityTcpProfile,
    WsTlsClient,
    WsTlsClientOverride,
    WsTlsProfile,
    XHttpClient,
    XHttpClientOverride,
    XHttpProfile,
    artifact_to_dict,
    parse_client_override,
    parse_overrides_map,
)
from .template import find_placeholder_fields, load_xray_template

_YAML_IMPORT_ERROR: ModuleNotFoundError | None = None
yaml: Any | None = None
try:
    yaml = importlib.import_module("yaml")
except ModuleNotFoundError as exc:
    _YAML_IMPORT_ERROR = exc

log = logging.getLogger("profiles.builder")


class ArtifactBuilder:
    """Build typed control-plane artifact from Xray template + overrides."""

    def __init__(self, *, strict: bool = True) -> None:
        self.strict = strict

    def build_payload(
        self,
        *,
        template_path: Path = XRAY_TEMPLATE_DEFAULT,
        overrides_path: Path = XRAY_OVERRIDES_DEFAULT,
    ) -> ArtifactPayload:
        xray_config = load_xray_template(template_path)
        overrides = self._load_overrides(overrides_path)

        inbounds = xray_config.get("inbounds")
        if not isinstance(inbounds, list):
            raise ArtifactBuildError("xray config must contain 'inbounds' list")

        artifact: dict[str, WsTlsProfile | RealityTcpProfile | XHttpProfile] = {}
        errors: list[str] = []
        seen_tags: set[str] = set()

        for inbound in inbounds:
            if not isinstance(inbound, dict):
                errors.append("found inbound entry that is not an object")
                continue

            tag = str(inbound.get("tag", "")).strip()
            if not tag:
                errors.append("found inbound without tag")
                continue

            if tag == "api":
                continue

            seen_tags.add(tag)
            override = overrides.get(tag, ProfileOverride())
            if not override.enabled:
                log.info("Skipping inbound '%s' (enabled=false in overrides)", tag)
                continue

            profile_type = self._resolve_profile_type(tag=tag, inbound=inbound, override=override)
            if profile_type not in SUPPORTED_PROFILE_TYPES:
                message = f"{tag}: unsupported profile type '{profile_type}'"
                if self.strict:
                    errors.append(message)
                else:
                    log.warning("%s", message)
                continue

            try:
                profile = self._build_profile(
                    tag=tag,
                    inbound=inbound,
                    profile_type=profile_type,
                    override=override,
                )
            except ArtifactBuildError as exc:
                errors.append(str(exc))
                continue

            profile_dump = profile.model_dump(mode="json", exclude_none=True)
            unresolved_fields = find_placeholder_fields(profile_dump)
            if unresolved_fields:
                message = (
                    f"{tag}: unresolved template placeholders in fields: "
                    + ", ".join(unresolved_fields)
                )
                if self.strict:
                    errors.append(message)
                    continue
                log.warning("%s", message)

            profile_key = str(override.key or _default_profile_key(tag)).strip()
            if not profile_key:
                errors.append(f"{tag}: profile key cannot be empty")
                continue

            if profile_key in artifact:
                errors.append(
                    f"{tag}: duplicate profile key '{profile_key}' "
                    "(already used by another inbound)"
                )
                continue

            artifact[profile_key] = profile

        unknown_override_tags = sorted(set(overrides) - seen_tags)
        if unknown_override_tags:
            errors.append(
                "Overrides defined for unknown inbound tags: " + ", ".join(unknown_override_tags)
            )

        if errors:
            raise ArtifactBuildError("Invalid xray->artifact conversion:\n" + "\n".join(errors))

        if not artifact:
            raise ArtifactBuildError("Generated artifact is empty")

        try:
            return ArtifactPayload(artifact=artifact)
        except ValidationError as exc:
            raise ArtifactBuildError(
                "Generated artifact does not satisfy control-plane schema:\n"
                f"{exc}"
            ) from exc

    def build_artifact(
        self,
        *,
        template_path: Path = XRAY_TEMPLATE_DEFAULT,
        overrides_path: Path = XRAY_OVERRIDES_DEFAULT,
    ) -> dict[str, dict[str, Any]]:
        payload = self.build_payload(template_path=template_path, overrides_path=overrides_path)
        return artifact_to_dict(payload.artifact)

    def _load_overrides(self, path: Path) -> dict[str, ProfileOverride]:
        if not path.exists():
            return {}

        if yaml is None:
            raise ArtifactBuildError(
                "PyYAML is required to read overrides. Install dependency: pip install pyyaml"
            ) from _YAML_IMPORT_ERROR

        raw_data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        if not isinstance(raw_data, dict):
            raise ArtifactBuildError(f"Overrides file must be a mapping: {path}")

        profiles_section = raw_data.get("profiles", raw_data)
        if not isinstance(profiles_section, dict):
            raise ArtifactBuildError(f"Overrides 'profiles' section must be a mapping: {path}")

        try:
            return parse_overrides_map(profiles_section)
        except ValidationError as exc:
            raise ArtifactBuildError(
                f"Invalid overrides format in {path}:\n{exc}"
            ) from exc

    def _resolve_profile_type(
        self,
        *,
        tag: str,
        inbound: dict[str, Any],
        override: ProfileOverride,
    ) -> str:
        if override.type:
            return override.type

        stream = inbound.get("streamSettings", {})
        if not isinstance(stream, dict):
            raise ArtifactBuildError(f"{tag}: streamSettings must be an object")

        security = stream.get("security")
        network = stream.get("network")

        if security == "reality":
            return "reality_tcp"
        if network == "ws":
            return "ws_tls"
        return "unsupported"

    def _build_profile(
        self,
        *,
        tag: str,
        inbound: dict[str, Any],
        profile_type: str,
        override: ProfileOverride,
    ) -> WsTlsProfile | RealityTcpProfile | XHttpProfile:
        if profile_type == "ws_tls":
            return self._build_ws_profile(tag=tag, inbound=inbound, override=override)
        if profile_type == "reality_tcp":
            return self._build_reality_profile(tag=tag, inbound=inbound, override=override)
        if profile_type == "xhttp":
            return self._build_xhttp_profile(tag=tag, inbound=inbound, override=override)
        raise ArtifactBuildError(f"{tag}: unsupported profile type '{profile_type}'")

    def _build_xhttp_profile(
        self,
        *,
        tag: str,
        inbound: dict[str, Any],
        override: ProfileOverride,
    ) -> XHttpProfile:
        stream = _as_dict(inbound.get("streamSettings"), field_path=f"{tag}.streamSettings")
        xhttp_settings = _as_dict(
            stream.get("xhttpSettings"),
            field_path=f"{tag}.streamSettings.xhttpSettings",
        )
        tls_settings = _as_dict(
            stream.get("tlsSettings"),
            field_path=f"{tag}.streamSettings.tlsSettings",
        )

        try:
            client_override = parse_client_override(
                profile_type="xhttp",
                raw_client_override=override.client,
            )
        except ValidationError as exc:
            raise ArtifactBuildError(f"{tag}: invalid xhttp client override:\n{exc}") from exc

        ov = client_override if isinstance(client_override, XHttpClientOverride) else None

        path = _pick_first_non_empty(ov.path if ov else None, xhttp_settings.get("path"))
        host = _pick_first_non_empty(ov.host if ov else None)
        sni = _pick_first_non_empty(ov.sni if ov else None, tls_settings.get("serverName"), host)

        missing = []
        if _is_blank(path):
            missing.append("client.path")
        if _is_blank(host):
            missing.append("client.host")
        if _is_blank(sni):
            missing.append("client.sni")
        if missing:
            raise ArtifactBuildError(f"{tag}: missing required fields: {', '.join(missing)}")

        kwargs: dict[str, Any] = {"path": str(path), "host": str(host), "sni": str(sni)}
        if ov and ov.mode:
            kwargs["mode"] = ov.mode
        if ov and ov.fingerprint:
            kwargs["fingerprint"] = ov.fingerprint
        if ov and ov.alpn:
            kwargs["alpn"] = ov.alpn
        if ov and ov.extra:
            kwargs["extra"] = ov.extra

        display_name = override.display_name or _default_display_name(tag)
        try:
            return XHttpProfile(display_name=display_name, client=XHttpClient(**kwargs))
        except ValidationError as exc:
            raise ArtifactBuildError(f"{tag}: invalid xhttp profile:\n{exc}") from exc

    def _build_ws_profile(
        self,
        *,
        tag: str,
        inbound: dict[str, Any],
        override: ProfileOverride,
    ) -> WsTlsProfile:
        stream = _as_dict(inbound.get("streamSettings"), field_path=f"{tag}.streamSettings")
        ws_settings = _as_dict(
            stream.get("wsSettings"),
            field_path=f"{tag}.streamSettings.wsSettings",
        )
        headers = _as_dict(
            ws_settings.get("headers"),
            field_path=f"{tag}.streamSettings.wsSettings.headers",
        )
        tls_settings = _as_dict(
            stream.get("tlsSettings"),
            field_path=f"{tag}.streamSettings.tlsSettings",
        )

        try:
            client_override = parse_client_override(
                profile_type="ws_tls",
                raw_client_override=override.client,
            )
        except ValidationError as exc:
            raise ArtifactBuildError(f"{tag}: invalid ws_tls client override:\n{exc}") from exc

        ws_override = client_override if isinstance(client_override, WsTlsClientOverride) else None

        path = _pick_first_non_empty(
            ws_override.path if ws_override else None,
            ws_settings.get("path"),
        )
        host = _pick_first_non_empty(
            ws_override.host if ws_override else None,
            headers.get("Host"),
            headers.get("host"),
        )
        sni = _pick_first_non_empty(
            ws_override.sni if ws_override else None,
            tls_settings.get("serverName"),
            host,
        )

        missing = []
        if _is_blank(path):
            missing.append("client.path")
        if _is_blank(host):
            missing.append("client.host")
        if _is_blank(sni):
            missing.append("client.sni")
        if missing:
            raise ArtifactBuildError(f"{tag}: missing required fields: {', '.join(missing)}")

        display_name = override.display_name or _default_display_name(tag)
        try:
            return WsTlsProfile(
                display_name=display_name,
                client=WsTlsClient(
                    path=str(path),
                    host=str(host),
                    sni=str(sni),
                ),
            )
        except ValidationError as exc:
            raise ArtifactBuildError(f"{tag}: invalid ws_tls profile:\n{exc}") from exc

    def _build_reality_profile(
        self,
        *,
        tag: str,
        inbound: dict[str, Any],
        override: ProfileOverride,
    ) -> RealityTcpProfile:
        stream = _as_dict(inbound.get("streamSettings"), field_path=f"{tag}.streamSettings")
        reality_settings = _as_dict(
            stream.get("realitySettings"),
            field_path=f"{tag}.streamSettings.realitySettings",
        )

        try:
            client_override = parse_client_override(
                profile_type="reality_tcp",
                raw_client_override=override.client,
            )
        except ValidationError as exc:
            raise ArtifactBuildError(f"{tag}: invalid reality_tcp client override:\n{exc}") from exc

        reality_override = (
            client_override if isinstance(client_override, RealityTcpClientOverride) else None
        )

        server_names = reality_settings.get("serverNames")
        short_ids = reality_settings.get("shortIds")

        sni = _pick_first_non_empty(
            reality_override.sni if reality_override else None,
            _first_string(server_names),
        )
        short_id = _pick_first_non_empty(
            reality_override.short_id if reality_override else None,
            _first_string(short_ids),
        )
        fingerprint = _pick_first_non_empty(
            reality_override.fingerprint if reality_override else None
        )
        public_key = _pick_first_non_empty(
            reality_override.public_key if reality_override else None
        )
        flow = _pick_first_non_empty(reality_override.flow if reality_override else None)
        spider_x = _pick_first_non_empty(
            reality_override.spider_x if reality_override else None
        )

        missing = []
        if _is_blank(sni):
            missing.append("client.sni")
        if _is_blank(fingerprint):
            missing.append("client.fingerprint")
        if _is_blank(public_key):
            missing.append("client.public_key")
        if _is_blank(short_id):
            missing.append("client.short_id")
        if missing:
            raise ArtifactBuildError(f"{tag}: missing required fields: {', '.join(missing)}")

        display_name = override.display_name or _default_display_name(tag)

        try:
            return RealityTcpProfile(
                display_name=display_name,
                client=RealityTcpClient(
                    sni=str(sni),
                    flow=str(flow) if flow is not None else None,
                    fingerprint=str(fingerprint),
                    public_key=str(public_key),
                    short_id=str(short_id),
                    spider_x=str(spider_x) if spider_x is not None else None,
                ),
            )
        except ValidationError as exc:
            raise ArtifactBuildError(f"{tag}: invalid reality_tcp profile:\n{exc}") from exc


def _as_dict(value: Any, *, field_path: str) -> dict[str, Any]:
    if value is None:
        return {}
    if isinstance(value, dict):
        return value
    raise ArtifactBuildError(f"{field_path} must be an object")


def _first_string(value: Any) -> str | None:
    if isinstance(value, list):
        for item in value:
            if isinstance(item, str) and item.strip():
                return item
    return None


def _pick_first_non_empty(*values: Any) -> str | None:
    for value in values:
        if isinstance(value, str) and value.strip():
            return value
    return None


def _is_blank(value: Any) -> bool:
    return not (isinstance(value, str) and value.strip())


def _default_display_name(tag: str) -> str:
    normalized = re.sub(r"[_-]+", " ", tag).strip()
    return normalized.title() if normalized else "Profile"


def _default_profile_key(tag: str) -> str:
    normalized = re.sub(r"[^a-zA-Z0-9_]+", "_", tag).strip("_").lower()
    if not normalized:
        normalized = "profile"
    return f"{normalized}_v1"


__all__ = ["ArtifactBuilder"]
