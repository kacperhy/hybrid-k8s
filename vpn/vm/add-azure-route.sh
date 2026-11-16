#!/usr/bin/env bash
# Na VM z k3s: dopisuje sieć Azure (VNet) do AllowedIPs peera Pi, żeby sondy
# z klastra onprem docierały do AKS (10.50.1.250). Uruchom NA VM jako root.
set -euo pipefail
VNET="${1:-10.50.0.0/16}"
CONF=/etc/wireguard/wg0.conf

grep -q "AllowedIPs.*${VNET}" "$CONF" && { echo "Już jest: $(grep AllowedIPs "$CONF")"; exit 0; }
cp "$CONF" "$CONF.bak.$(date +%s)"
sed -i -E "s#^(AllowedIPs *= *.*)#\1, ${VNET}#" "$CONF"
grep AllowedIPs "$CONF"
systemctl restart wg-quick@wg0
sleep 2
ip route | grep wg0
