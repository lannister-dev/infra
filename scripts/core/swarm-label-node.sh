#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  echo "[SWARM][LABEL][ERROR] $*" >&2
  exit 1
}

NODE_ID=""
CHANNEL=""
PEER_NAME=""
TRAFFIC_ROLE="standard"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --node-id)
      NODE_ID="${2:-}"
      shift 2
      ;;
    --channel)
      CHANNEL="${2:-}"
      shift 2
      ;;
    --peer-name)
      PEER_NAME="${2:-}"
      shift 2
      ;;
    --traffic-role)
      TRAFFIC_ROLE="${2:-}"
      shift 2
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${NODE_ID}" ]] || fail "--node-id is required"
[[ -n "${CHANNEL}" ]] || fail "--channel is required"
[[ -n "${PEER_NAME}" ]] || fail "--peer-name is required"
[[ -n "${TRAFFIC_ROLE}" ]] || fail "--traffic-role is required"
[[ "${TRAFFIC_ROLE}" == "standard" || "${TRAFFIC_ROLE}" == "whitelist_entry" ]] || fail "--traffic-role must be standard or whitelist_entry"
command -v docker >/dev/null 2>&1 || fail "docker CLI not found"

cur_role="$(docker node inspect --format '{{ index .Spec.Labels "role" }}' "${NODE_ID}" 2>/dev/null || true)"
cur_channel="$(docker node inspect --format '{{ index .Spec.Labels "channel" }}' "${NODE_ID}" 2>/dev/null || true)"
cur_peer="$(docker node inspect --format '{{ index .Spec.Labels "peer_name" }}' "${NODE_ID}" 2>/dev/null || true)"
cur_traffic_role="$(docker node inspect --format '{{ index .Spec.Labels "traffic_role" }}' "${NODE_ID}" 2>/dev/null || true)"

if [[ "${cur_role}" == "vpn" && "${cur_channel}" == "${CHANNEL}" && "${cur_peer}" == "${PEER_NAME}" && "${cur_traffic_role}" == "${TRAFFIC_ROLE}" ]]; then
  exit 0
fi

docker node update \
  --label-add "role=vpn" \
  --label-add "channel=${CHANNEL}" \
  --label-add "peer_name=${PEER_NAME}" \
  --label-add "traffic_role=${TRAFFIC_ROLE}" \
  "${NODE_ID}" >/dev/null

exit 10
