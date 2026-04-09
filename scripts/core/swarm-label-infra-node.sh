#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  echo "[SWARM][LABEL][INFRA][ERROR] $*" >&2
  exit 1
}

NODE_ID=""
KIND=""
INFRA_NAME=""
PROVIDER=""
REGION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --node-id)
      NODE_ID="${2:-}"
      shift 2
      ;;
    --kind)
      KIND="${2:-}"
      shift 2
      ;;
    --infra-name)
      INFRA_NAME="${2:-}"
      shift 2
      ;;
    --provider)
      PROVIDER="${2:-}"
      shift 2
      ;;
    --region)
      REGION="${2:-}"
      shift 2
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${NODE_ID}" ]] || fail "--node-id is required"
[[ -n "${KIND}" ]] || fail "--kind is required"
[[ -n "${INFRA_NAME}" ]] || fail "--infra-name is required"
command -v docker >/dev/null 2>&1 || fail "docker CLI not found"

cur_kind="$(docker node inspect --format '{{ index .Spec.Labels "kind" }}' "${NODE_ID}" 2>/dev/null || true)"
cur_infra_name="$(docker node inspect --format '{{ index .Spec.Labels "infra_name" }}' "${NODE_ID}" 2>/dev/null || true)"
cur_provider="$(docker node inspect --format '{{ index .Spec.Labels "provider" }}' "${NODE_ID}" 2>/dev/null || true)"
cur_region="$(docker node inspect --format '{{ index .Spec.Labels "region" }}' "${NODE_ID}" 2>/dev/null || true)"

if [[ "${cur_kind}" == "${KIND}" && "${cur_infra_name}" == "${INFRA_NAME}" && "${cur_provider}" == "${PROVIDER}" && "${cur_region}" == "${REGION}" ]]; then
  exit 0
fi

cmd=(docker node update --label-add "kind=${KIND}" --label-add "infra_name=${INFRA_NAME}")

if [[ -n "${PROVIDER}" ]]; then
  cmd+=(--label-add "provider=${PROVIDER}")
elif [[ -n "${cur_provider}" && "${cur_provider}" != "<no value>" ]]; then
  cmd+=(--label-rm provider)
fi

if [[ -n "${REGION}" ]]; then
  cmd+=(--label-add "region=${REGION}")
elif [[ -n "${cur_region}" && "${cur_region}" != "<no value>" ]]; then
  cmd+=(--label-rm region)
fi

cmd+=("${NODE_ID}")
"${cmd[@]}" >/dev/null

exit 10
