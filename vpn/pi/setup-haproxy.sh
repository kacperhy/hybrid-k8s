#!/usr/bin/env bash
# Instaluje HAProxy na Raspberry Pi i ustawia przełączanie ruchu onprem -> AKS.
# Uruchom NA PI jako root, z katalogu vpn/pi:   sudo ./setup-haproxy.sh
set -euo pipefail
cd "$(dirname "$0")"
VPN_IP=10.10.20.1
VPN_CIDR=10.10.20.0/24

if ss -ltn | grep -qE "(${VPN_IP}|0\.0\.0\.0|\*|\[::\]):(8080|8404) "; then
  echo "[!] Coś już nasłuchuje na porcie 80 lub 8404 – sprawdź: ss -ltnp | grep -E ':(8080|8404) '"
  exit 1
fi

apt-get update -qq && apt-get install -y -qq haproxy

# HAProxy wiąże się z adresem VPN; pozwól na to także zanim wg0 wstanie przy starcie
echo 'net.ipv4.ip_nonlocal_bind = 1' > /etc/sysctl.d/99-haproxy-nonlocal.conf
sysctl -q --system

[[ -f /etc/haproxy/haproxy.cfg.orig ]] || cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.orig
install -m 644 haproxy.cfg /etc/haproxy/haproxy.cfg
haproxy -c -f /etc/haproxy/haproxy.cfg

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow in on wg0 from "$VPN_CIDR" to "$VPN_IP" port 8080 proto tcp
  ufw allow in on wg0 from "$VPN_CIDR" to "$VPN_IP" port 8404 proto tcp
fi

systemctl enable haproxy
systemctl restart haproxy
systemctl --no-pager --lines=0 status haproxy
echo "Gotowe. Z klienta VPN:  curl http://${VPN_IP}:8080/api/info   oraz panel: http://${VPN_IP}:8404/"
