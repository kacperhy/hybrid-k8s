#!/usr/bin/env bash
# Blokuje dostęp do aplikacji k3s z sieci LAN – zostaje tylko VPN.
#
# Dlaczego: k3s (ServiceLB/hostPort i NodePorty) przekierowuje ruch na porty 80/443
# i 30000-32767 regułą DNAT w PREROUTING, ZANIM pakiet trafi do filtrów UFW
# (ruch idzie potem łańcuchem FORWARD, gdzie k3s ma własne reguły ACCEPT).
# UFW "deny incoming" tego nie zatrzyma. Odrzucamy więc nowe połączenia na tych
# portach już w tabeli mangle, na interfejsie LAN – przed DNAT.
#
# Reguła jest dodawana przez usługę systemd przy każdym starcie (idempotentnie).
# Uruchamiaj NA VM:  sudo ./scripts/12-block-lan.sh
set -euo pipefail

LAN_IF="${LAN_IF:-$(ip route show default | awk '{print $5; exit}')}"
[[ -n "$LAN_IF" ]] || { echo "Nie wykryłem interfejsu LAN – podaj LAN_IF=ens33"; exit 1; }
PORTS="80,443,30000:32767"

cat > /usr/local/sbin/hybrid-lan-block <<EOF
#!/bin/sh
# Generowane przez hybrid-k8s/scripts/12-block-lan.sh
RULE="-i ${LAN_IF} -p tcp -m multiport --dports ${PORTS} -m conntrack --ctstate NEW -j DROP"
iptables -t mangle -C PREROUTING \$RULE 2>/dev/null || iptables -t mangle -I PREROUTING 1 \$RULE
EOF
chmod 755 /usr/local/sbin/hybrid-lan-block

cat > /etc/systemd/system/hybrid-lan-block.service <<'EOF'
[Unit]
Description=hybrid-k8s: porty aplikacji k3s tylko z VPN (blokada LAN)
After=network-online.target ufw.service k3s.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hybrid-lan-block
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now hybrid-lan-block.service
echo "Reguła na interfejsie ${LAN_IF}:"
iptables -t mangle -S PREROUTING | grep -- "--dports ${PORTS}"
