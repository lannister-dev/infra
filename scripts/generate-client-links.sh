#!/usr/bin/env bash
set -Eeuo pipefail

UUID="$1"
EMAIL="$2"
USER="${EMAIL%@*}"

# Wi-Fi (WS)
echo "vless://${UUID}@${VPN_DOMAIN}:443\
?encryption=none\
&security=tls\
&type=ws\
&host=${VPN_DOMAIN}\
&path=$(echo -n "${VPN_WS_PATH}" | jq -sRr @uri)\
&sni=${VPN_DOMAIN}\
#${USER}-wifi"

# Mobile (XHTTP)
echo "vless://${UUID}@${VPN_DOMAIN}:443\
?encryption=none\
&security=tls\
&type=xhttp\
&path=$(echo -n "${VPN_XHTTP_PATH}" | jq -sRr @uri)\
&sni=${VPN_DOMAIN}\
#${USER}-mobile"