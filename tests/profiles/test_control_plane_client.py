from __future__ import annotations

from typing import Any

from services.profiles.api.client import ControlPlaneClient


def test_publish_and_reload_close_session_each_call(monkeypatch) -> None:
    client = ControlPlaneClient(base_url="https://cp.example", api_key="token", timeout_s=1.0)
    calls: list[tuple[str, str, Any]] = []

    async def fake_post(path: str, *, json: dict[str, Any] | None = None, params=None) -> Any:
        calls.append(("post", path, json))
        if path == "/profiles/publish":
            return {"version": 7, "checksum": "deadbeef"}
        return {"status": "ok"}

    async def fake_close() -> None:
        calls.append(("close", "", None))

    monkeypatch.setattr(client, "post", fake_post)
    monkeypatch.setattr(client, "close", fake_close)

    published = client.publish_artifact({"ws_tls_v1": {"type": "ws_tls"}})
    reloaded = client.reload_registry()

    assert published["version"] == 7
    assert reloaded["status"] == "ok"
    assert calls == [
        ("post", "/profiles/publish", {"artifact": {"ws_tls_v1": {"type": "ws_tls"}}}),
        ("close", "", None),
        ("post", "/profiles/reload", None),
        ("close", "", None),
    ]
