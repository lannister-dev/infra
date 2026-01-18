#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLIENTS_FILE="/var/lib/vpn/clients.json"

cmd_add() {
  local email="$1"
  local uuid
  uuid="$(uuidgen | tr A-Z a-z)"

  jq --arg email "$email" --arg id "$uuid" \
    '. += [{"id": $id, "email": $email, "level": 0}]' \
    "$CLIENTS_FILE" > "$CLIENTS_FILE.tmp"

  mv "$CLIENTS_FILE.tmp" "$CLIENTS_FILE"
  echo "$uuid"
}

cmd_remove() {
  local email="$1"
  jq --arg email "$email" \
    'map(select(.email != $email))' \
    "$CLIENTS_FILE" > "$CLIENTS_FILE.tmp"
  mv "$CLIENTS_FILE.tmp" "$CLIENTS_FILE"
}

case "$1" in
  add)    cmd_add "$2" ;;
  remove) cmd_remove "$2" ;;
  *) echo "usage: clients.sh add|remove email" ;;
esac