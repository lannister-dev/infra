#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  echo "[DIR][COPY][ERROR] $*" >&2
  exit 1
}

SOURCE_HOST=""
SOURCE_USER=""
SOURCE_PORT="22"
SOURCE_KEY_FILE=""
SOURCE_PATH=""
TARGET_HOST=""
TARGET_USER=""
TARGET_PORT="22"
TARGET_KEY_FILE=""
TARGET_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-host) SOURCE_HOST="${2:-}"; shift 2 ;;
    --source-user) SOURCE_USER="${2:-}"; shift 2 ;;
    --source-port) SOURCE_PORT="${2:-}"; shift 2 ;;
    --source-key-file) SOURCE_KEY_FILE="${2:-}"; shift 2 ;;
    --source-path) SOURCE_PATH="${2:-}"; shift 2 ;;
    --target-host) TARGET_HOST="${2:-}"; shift 2 ;;
    --target-user) TARGET_USER="${2:-}"; shift 2 ;;
    --target-port) TARGET_PORT="${2:-}"; shift 2 ;;
    --target-key-file) TARGET_KEY_FILE="${2:-}"; shift 2 ;;
    --target-path) TARGET_PATH="${2:-}"; shift 2 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "${SOURCE_HOST}" ]] || fail "--source-host is required"
[[ -n "${SOURCE_USER}" ]] || fail "--source-user is required"
[[ -n "${SOURCE_KEY_FILE}" ]] || fail "--source-key-file is required"
[[ -n "${SOURCE_PATH}" ]] || fail "--source-path is required"
[[ -n "${TARGET_HOST}" ]] || fail "--target-host is required"
[[ -n "${TARGET_USER}" ]] || fail "--target-user is required"
[[ -n "${TARGET_KEY_FILE}" ]] || fail "--target-key-file is required"
[[ -n "${TARGET_PATH}" ]] || fail "--target-path is required"
[[ "${SOURCE_PATH}" != "/" ]] || fail "--source-path must not be /"
[[ "${TARGET_PATH}" != "/" ]] || fail "--target-path must not be /"

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

"${source_ssh[@]}" "test -d '${SOURCE_PATH}'" || fail "Source directory does not exist: ${SOURCE_PATH}"

if [[ "${SOURCE_HOST}" == "${TARGET_HOST}" && "${SOURCE_PATH}" == "${TARGET_PATH}" ]]; then
  fail "Source and target directories are identical: ${SOURCE_PATH}"
fi

"${target_ssh[@]}" "mkdir -p '${TARGET_PATH}' && find '${TARGET_PATH}' -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +"

"${source_ssh[@]}" "tar -C '${SOURCE_PATH}' -cpf - ." \
  | "${target_ssh[@]}" "tar -C '${TARGET_PATH}' -xpf -"
