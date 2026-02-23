#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_DIRS=(
  "terraform/foundation"
  "terraform/nodes"
  "terraform/infra-nodes"
)

for module_dir in "${MODULE_DIRS[@]}"; do
  full_path="${ROOT_DIR}/${module_dir}"
  echo "[locks] ${module_dir}"
  terraform -chdir="${full_path}" init -backend=false -input=false >/dev/null
  terraform -chdir="${full_path}" providers lock \
    -platform=linux_amd64 \
    -platform=darwin_amd64 \
    -platform=darwin_arm64 \
    -platform=windows_amd64 >/dev/null
done

echo "[locks] updated .terraform.lock.hcl files"
