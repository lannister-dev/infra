#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  echo "[VOLUME][COPY][ERROR] $*" >&2
  exit 1
}

SOURCE_HOST=""
SOURCE_USER=""
SOURCE_PORT="22"
SOURCE_KEY_FILE=""
TARGET_HOST=""
TARGET_USER=""
TARGET_PORT="22"
TARGET_KEY_FILE=""
VOLUME_NAME=""
TARGET_VOLUME_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-host) SOURCE_HOST="${2:-}"; shift 2 ;;
    --source-user) SOURCE_USER="${2:-}"; shift 2 ;;
    --source-port) SOURCE_PORT="${2:-}"; shift 2 ;;
    --source-key-file) SOURCE_KEY_FILE="${2:-}"; shift 2 ;;
    --target-host) TARGET_HOST="${2:-}"; shift 2 ;;
    --target-user) TARGET_USER="${2:-}"; shift 2 ;;
    --target-port) TARGET_PORT="${2:-}"; shift 2 ;;
    --target-key-file) TARGET_KEY_FILE="${2:-}"; shift 2 ;;
    --volume) VOLUME_NAME="${2:-}"; shift 2 ;;
    --target-volume) TARGET_VOLUME_NAME="${2:-}"; shift 2 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "${SOURCE_HOST}" ]] || fail "--source-host is required"
[[ -n "${SOURCE_USER}" ]] || fail "--source-user is required"
[[ -n "${SOURCE_KEY_FILE}" ]] || fail "--source-key-file is required"
[[ -n "${TARGET_HOST}" ]] || fail "--target-host is required"
[[ -n "${TARGET_USER}" ]] || fail "--target-user is required"
[[ -n "${TARGET_KEY_FILE}" ]] || fail "--target-key-file is required"
[[ -n "${VOLUME_NAME}" ]] || fail "--volume is required"
[[ -n "${TARGET_VOLUME_NAME}" ]] || TARGET_VOLUME_NAME="${VOLUME_NAME}"

ssh_common=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=yes
  -o ConnectTimeout=15
)

source_ssh=(
  ssh "${ssh_common[@]}"
  -i "${SOURCE_KEY_FILE}"
  -p "${SOURCE_PORT}"
  "${SOURCE_USER}@${SOURCE_HOST}"
)

target_ssh=(
  ssh "${ssh_common[@]}"
  -i "${TARGET_KEY_FILE}"
  -p "${TARGET_PORT}"
  "${TARGET_USER}@${TARGET_HOST}"
)

src_mount="$("${source_ssh[@]}" "docker volume inspect -f '{{ .Mountpoint }}' '${VOLUME_NAME}'")"
[[ -n "${src_mount}" ]] || fail "Could not resolve source mountpoint for volume ${VOLUME_NAME}"

"${target_ssh[@]}" "docker volume create '${TARGET_VOLUME_NAME}' >/dev/null"
dst_mount="$("${target_ssh[@]}" "docker volume inspect -f '{{ .Mountpoint }}' '${TARGET_VOLUME_NAME}'")"
[[ -n "${dst_mount}" ]] || fail "Could not resolve target mountpoint for volume ${TARGET_VOLUME_NAME}"

if [[ "${SOURCE_HOST}" == "${TARGET_HOST}" && "${src_mount}" == "${dst_mount}" ]]; then
  fail "Source and target volume mountpoints are identical for ${VOLUME_NAME} -> ${TARGET_VOLUME_NAME}"
fi

"${source_ssh[@]}" "tar -C '${src_mount}' -cpf - ." \
  | "${target_ssh[@]}" "mkdir -p '${dst_mount}' && find '${dst_mount}' -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C '${dst_mount}' -xpf -"
