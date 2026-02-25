#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  echo "[SWARM][REGISTRY-AUTH][ERROR] $*" >&2
  exit 1
}

SERVICE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)
      SERVICE="${2:-}"
      shift 2
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${SERVICE}" ]] || fail "--service is required"
command -v docker >/dev/null 2>&1 || fail "docker CLI not found"

if ! docker service inspect "${SERVICE}" >/dev/null 2>&1; then
  exit 0
fi

docker service update --with-registry-auth --detach "${SERVICE}" >/dev/null
exit 10
