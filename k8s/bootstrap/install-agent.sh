#!/usr/bin/env bash
# ============================================================
# K3s Agent (Worker Node) Installation
#
# Что делает:
#   1. Ставит K3s в режиме agent (worker)
#   2. Подключается к существующему server по URL + token
#   3. Навешивает labels/taints на ноду
#   4. Прокидывает произвольные k3s agent флаги через --extra-arg
#
# Использование:
#   ./install-agent.sh --url https://<server-ip>:6443 --token <node-token> \
#       --label role=vpn --label channel=prod \
#       --taint dedicated=vpn:NoSchedule
#
# Для нод где eth0 не имеет публичного IP (1:1 NAT cloud: Yandex Cloud,
# AWS, GCP) передать публичный адрес явно, чтобы k3s отрепортил его как
# InternalIP — иначе кластер не достучится до hostNetwork-подов и
# kubelet'а:
#
#   --extra-arg '--node-ip=158.160.231.247' \
#   --extra-arg '--flannel-iface=eth0'
#
# Скрипт идемпотентен: повторный запуск с другим набором флагов
# перезапишет systemd unit через get.k3s.io и рестартует сервис.
# ============================================================
set -Eeuo pipefail

K3S_URL=""
K3S_TOKEN=""
K3S_VERSION=""
LABEL_ARGS=""
TAINT_ARGS=""
EXTRA_ARGS=""

usage() {
    echo "Usage: $0 --url <server_url> --token <node_token> [OPTIONS]"
    echo "  --url <url>              K3s server URL (required, e.g. https://10.0.0.1:6443)"
    echo "  --token <token>          K3s node token (required, from server)"
    echo "  --version <version>      K3s version (should match server)"
    echo "  --label <key=value>      Node label (repeatable)"
    echo "  --taint <key=val:effect> Node taint (repeatable)"
    echo "  --extra-arg <arg>        Pass-through k3s agent flag (repeatable)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)
            K3S_URL="$2"
            shift 2
            ;;
        --token)
            K3S_TOKEN="$2"
            shift 2
            ;;
        --version)
            K3S_VERSION="$2"
            shift 2
            ;;
        --label)
            LABEL_ARGS="${LABEL_ARGS} --node-label=$2"
            shift 2
            ;;
        --taint)
            TAINT_ARGS="${TAINT_ARGS} --node-taint=$2"
            shift 2
            ;;
        --extra-arg)
            EXTRA_ARGS="${EXTRA_ARGS} $2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -z "${K3S_URL}" || -z "${K3S_TOKEN}" ]]; then
    echo "Error: --url and --token are required."
    echo ""
    usage
fi

echo "=== Installing K3s Agent ==="
echo "Server URL: ${K3S_URL}"
echo "Labels:     ${LABEL_ARGS:-none}"
echo "Taints:     ${TAINT_ARGS:-none}"
echo "Extra:      ${EXTRA_ARGS:-none}"
echo ""

export K3S_URL
export K3S_TOKEN
export INSTALL_K3S_VERSION="${K3S_VERSION}"
export INSTALL_K3S_EXEC="agent${EXTRA_ARGS}${LABEL_ARGS}${TAINT_ARGS}"

curl -sfL https://get.k3s.io | sh -

echo ""
echo "=== K3s Agent Installed ==="
echo "The node should appear in 'kubectl get nodes' on the server within 30 seconds."
