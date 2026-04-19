#!/usr/bin/env bash
# ============================================================
# K3s Agent (Worker Node) Installation
#
# Что делает:
#   1. Ставит K3s в режиме agent (worker)
#   2. Подключается к существующему server по URL + token
#   3. Навешивает labels на ноду (role=vpn, channel=prod, etc.)
#   4. Опционально ставит taints (чтобы на VPN ноду не попадали чужие поды)
#
# Использование:
#   ./install-agent.sh --url https://<server-ip>:6443 --token <node-token> \
#       --label role=vpn --label channel=prod \
#       --taint dedicated=vpn:NoSchedule
#
# Для нод в Yandex Cloud (VM за приватной подсетью) обязательно передать:
#       --label provider=yandex-cloud
#   и задать hostname `vpn-yc-*`. Prometheus скрейпит такие ноды через
#   ExternalIP (см. k8s/values/prod/monitoring.yaml) — без метки kubelet/
#   node-exporter target'ы будут висеть таймаутом.
#
# После установки:
#   - Нода появится в: kubectl get nodes (на server)
#   - Поды будут запланированы автоматически (если DaemonSet/nodeSelector совпадёт)
# ============================================================
set -Eeuo pipefail

K3S_URL=""
K3S_TOKEN=""
K3S_VERSION=""
LABEL_ARGS=""
TAINT_ARGS=""
EXTRA_ARGS=""
MONITORING_SOURCE_CIDR="82.97.253.81/32"

usage() {
    echo "Usage: $0 --url <server_url> --token <node_token> [OPTIONS]"
    echo "  --url <url>              K3s server URL (required, e.g. https://10.0.0.1:6443)"
    echo "  --token <token>          K3s node token (required, from server)"
    echo "  --version <version>      K3s version (should match server)"
    echo "  --label <key=value>      Node label (repeatable)"
    echo "  --taint <key=val:effect> Node taint (repeatable)"
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
echo "Labels: ${LABEL_ARGS:-none}"
echo "Taints: ${TAINT_ARGS:-none}"
echo ""

export K3S_URL
export K3S_TOKEN
export INSTALL_K3S_VERSION="${K3S_VERSION}"
export INSTALL_K3S_EXEC="agent ${LABEL_ARGS} ${TAINT_ARGS}"

curl -sfL https://get.k3s.io | sh -

# YC ноды сидят за ufw с default DROP. Открываем kubelet/node-exporter
# для Prometheus-хоста, иначе scrape'ы таймаутят несмотря на открытую SG.
if [[ "${LABEL_ARGS}" == *"provider=yandex-cloud"* ]]; then
    if command -v ufw >/dev/null 2>&1; then
        echo ""
        echo "=== Opening ufw for Prometheus (${MONITORING_SOURCE_CIDR}) ==="
        ufw allow from "${MONITORING_SOURCE_CIDR}" to any port 10250 proto tcp
        ufw allow from "${MONITORING_SOURCE_CIDR}" to any port 9100  proto tcp
    fi
fi

echo ""
echo "=== K3s Agent Installed ==="
echo "The node should appear in 'kubectl get nodes' on the server within 30 seconds."
