#!/usr/bin/env bash
set -e

NODE_NAME=$(hostname)
WG_DIR=/etc/wireguard
PRIV_KEY_FILE=$WG_DIR/privatekey

if [ ! -f "$PRIV_KEY_FILE" ]; then
  umask 077
  wg genkey | tee $PRIV_KEY_FILE | wg pubkey > $WG_DIR/publickey
  echo "[+] Generated WireGuard keys"
fi

PRIVATE_KEY=$(cat $PRIV_KEY_FILE)

python3 - <<EOF
import yaml, os
from jinja2 import Template

with open("peers.yaml") as f:
    data = yaml.safe_load(f)

node = data["nodes"]["$NODE_NAME"]
tpl = Template(open("wg0.conf.j2").read())

conf = tpl.render(
    node_name="$NODE_NAME",
    node=node,
    nodes=data["nodes"],
    network=data["network"],
    private_key=os.environ["PRIVATE_KEY"]
)

with open("/etc/wireguard/wg0.conf", "w") as f:
    f.write(conf)
EOF

systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

wg show