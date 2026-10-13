#!/usr/bin/env bash
# Instalacja klastra lokalnego (k3s, single-node) na komputerze stacjonarnym z Ubuntu.
# Uruchamiaj NA TYM komputerze.
source "$(dirname "$0")/lib.sh"
load_config
need curl

SAN_ARGS=""
for san in ${K3S_TLS_SAN//,/ }; do SAN_ARGS+=" --tls-san ${san}"; done

log "Instaluję k3s (z wbudowanym Traefikiem i ServiceLB)"
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --write-kubeconfig-mode 0644${SAN_ARGS}" sh -

log "Czekam na węzeł"
until sudo k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'; do sleep 3; done

log "Dodaję kontekst 'onprem' do ~/.kube/config"
mkdir -p ~/.kube
TMP=$(mktemp)
sed -e 's/: default$/: onprem/' /etc/rancher/k3s/k3s.yaml > "$TMP"
if [[ -f ~/.kube/config ]]; then
  KUBECONFIG=~/.kube/config:"$TMP" kubectl config view --flatten > ~/.kube/config.new
  mv ~/.kube/config.new ~/.kube/config
else
  cp "$TMP" ~/.kube/config
fi
chmod 600 ~/.kube/config; rm -f "$TMP"
kubectl --context onprem get nodes -o wide

if command -v ufw >/dev/null && sudo ufw status | grep -q active; then
  log "UFW: otwieram 80/443 (Ingress) – API 6443 tylko z sieci VPN"
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw allow from 10.10.20.0/24 to any port 6443 proto tcp
  # ruch wewnątrzklastrowy k3s (flannel/pods/services)
  sudo ufw allow from 10.42.0.0/16
  sudo ufw allow from 10.43.0.0/16
fi

warn "Pamiętaj: przekierowanie portów 80 i 443 na routerze -> ten komputer,"
warn "oraz rekord DNS onprem.${DOMAIN} -> Twoje publiczne IP (dopisz go do skryptu DDNS)."
