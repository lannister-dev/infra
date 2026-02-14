from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from .errors import ArtifactBuildError

PLACEHOLDER_TOKEN_RE = re.compile(r"__([A-Za-z_][A-Za-z0-9_]*)__")


def load_xray_template(path: Path) -> dict[str, Any]:
    """Load Xray JSON template and replace env placeholders with parse-safe stubs."""

    if not path.exists():
        raise ArtifactBuildError(f"Xray template not found: {path}")

    rendered = _render_template_for_json_parse(path.read_text(encoding="utf-8"))

    try:
        data = json.loads(rendered)
    except json.JSONDecodeError as exc:
        raise ArtifactBuildError(
            f"Invalid JSON after template rendering: {path} (line {exc.lineno}, col {exc.colno})"
        ) from exc

    if not isinstance(data, dict):
        raise ArtifactBuildError("xray template root must be a JSON object")

    return data


def _render_template_for_json_parse(raw_template: str) -> str:
    rendered = raw_template.replace("${VPN_CLIENTS_JSON}", "[]")
    rendered = re.sub(
        r'"\$\{([A-Za-z_][A-Za-z0-9_]*)\}"',
        lambda match: json.dumps(_placeholder_for_var(match.group(1))),
        rendered,
    )
    rendered = re.sub(
        r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}",
        lambda match: json.dumps(_placeholder_for_var(match.group(1))),
        rendered,
    )
    return rendered


def _placeholder_for_var(name: str) -> str:
    # Keep placeholders detectable in strict mode while preserving rough shape.
    if name.upper().endswith("_PATH"):
        return f"/__{name}__"
    return f"__{name}__"


def find_placeholder_fields(value: Any, prefix: str = "") -> list[str]:
    fields: list[str] = []

    if isinstance(value, dict):
        for key, nested in value.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            fields.extend(find_placeholder_fields(nested, path))
        return fields

    if isinstance(value, list):
        for index, nested in enumerate(value):
            path = f"{prefix}[{index}]"
            fields.extend(find_placeholder_fields(nested, path))
        return fields

    if isinstance(value, str) and PLACEHOLDER_TOKEN_RE.search(value):
        fields.append(prefix or "<root>")

    return fields


__all__ = ["find_placeholder_fields", "load_xray_template"]
