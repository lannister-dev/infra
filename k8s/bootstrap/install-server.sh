#!/usr/bin/env bash
# ============================================================
# K3s Server (Control Plane) Installation
#
# Что делает:
#   1. Ставит K3s в режиме server (control plane)
#   2. Настраивает Flannel backend для сети между подами
#   3. Добавляет TLS SAN (чтобы kubectl работал по внешнему IP)
#   4. Ждёт готовности API server
#   5. Выводит node token для подключения agents
#
# Использование:
#   ./install-server.sh [--tls-san <ip_or_dns>] [--flannel-backend wireguard-native]
#
# После установки:
#   - kubectl работает: k3s kubectl get nodes
#   - kubeconfig: /etc/rancher/k3s/k3s.yaml
#   - node token: /var/lib/rancher/k3s/server/node-token
# ============================================================
set -Eeuo pipefail

TLS_SAN=""
FLANNEL_BACKEND="vxlan"
K3S_VERSION=""
DISABLE_COMPONENTS=""

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "  --tls-san <ip|dns>          Add TLS SAN to API cert (repeatable)"
    echo "  --flannel-backend <backend>  Flannel backend: vxlan|wireguard-native|host-gw (default: vxlan)"
    echo "  --version <version>          K3s version (e.g. v1.31.4+k3s1)"
    echo "  --disable <component>        Disable component: traefik, servicelb (repeatable)"
    exit 1
}

TLS_SAN_ARGS=""
DISABLE_ARGS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tls-san)
            TLS_SAN_ARGS="${TLS_SAN_ARGS} --tls-san=$2"
            shift 2
            ;;
        --flannel-backend)
            FLANNEL_BACKEND="$2"
            shift 2
            ;;
        --version)
            K3S_VERSION="$2"
            shift 2
            ;;
        --disable)
            DISABLE_ARGS="${DISABLE_ARGS} --disable=$2"
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

echo "=== Installing K3s Server ==="
echo "Flannel backend: ${FLANNEL_BACKEND}"
echo "TLS SANs: ${TLS_SAN_ARGS:-none}"
echo "Disabled: ${DISABLE_ARGS:-none}"
echo ""

# Install K3s
export INSTALL_K3S_VERSION="${K3S_VERSION}"
export INSTALL_K3S_EXEC="server --flannel-backend=${FLANNEL_BACKEND} ${TLS_SAN_ARGS} ${DISABLE_ARGS}"

curl -sfL https://get.k3s.io | sh -

# Wait for API server
echo ""
echo "=== Waiting for K3s API server ==="
for i in $(seq 1 60); do
    if k3s kubectl get nodes &>/dev/null; then
        echo "K3s API server is ready."
        break
    fi
    echo "  attempt ${i}/60..."
    sleep 5
done

echo ""
echo "=== K3s Server Installed ==="
echo ""
k3s kubectl get nodes -o wide
echo ""
echo "Node token (for agents):"
cat /var/lib/rancher/k3s/server/node-token
echo ""
echo "Kubeconfig: /etc/rancher/k3s/k3s.yaml"
echo "To use kubectl remotely, copy kubeconfig and replace 127.0.0.1 with server IP."
