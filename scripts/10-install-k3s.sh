#!/usr/bin/env bash
# Instalacja klastra lokalnego (k3s, single-node) na VM z Ubuntu Server.
# Wariant VPN: klaster jest dostępny WYŁĄCZNIE z sieci WireGuard (VPN_CIDR),
# nic nie jest przekierowane na routerze. Uruchamiaj NA VM.
source "$(dirname "$0")/lib.sh"
load_config
need curl sudo

VPN_CIDR="${VPN_CIDR:-10.10.20.0/24}"
NODE_IP="${K3S_NODE_IP:-${K3S_TLS_SAN%%,*}}"   # adres VM w VPN, np. 10.10.20.6

ip -4 addr | grep -q "inet ${NODE_IP}/" || die "VM nie ma adresu ${NODE_IP} – czy WireGuard (wg0) jest podniesiony?"

# --- Firewall: najpierw reguły, potem włączenie (żeby nie odciąć SSH) -------------
if command -v ufw >/dev/null; then
  log "UFW: SSH, HTTP/HTTPS i API Kubernetesa tylko z sieci VPN ${VPN_CIDR}"
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow from "$VPN_CIDR" to any port 22  proto tcp
  sudo ufw allow from "$VPN_CIDR" to any port 80  proto tcp
  sudo ufw allow from "$VPN_CIDR" to any port 443 proto tcp
  sudo ufw allow from "$VPN_CIDR" to any port 6443 proto tcp
  [[ -n "${LAN_CIDR:-}" ]] && sudo ufw allow from "$LAN_CIDR" to any port 22 proto tcp
  # ruch wewnątrz klastra k3s (pody i serwisy)
  sudo ufw allow from 10.42.0.0/16
  sudo ufw allow from 10.43.0.0/16
  sudo ufw --force enable
  sudo ufw status numbered
fi

# --- k3s -----------------------------------------------------------------------------
SAN_ARGS=""
for san in ${K3S_TLS_SAN//,/ }; do SAN_ARGS+=" --tls-san ${san}"; done

log "Instaluję k3s (wbudowany Traefik i ServiceLB), node-ip=${NODE_IP}"
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --write-kubeconfig-mode 0644 --node-ip ${NODE_IP}${SAN_ARGS}" sh -

log "Czekam na węzeł"
until sudo k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'; do sleep 3; done

log "Dodaję kontekst 'onprem' do ~/.kube/config"
mkdir -p ~/.kube
TMP=$(mktemp)
sed -e 's/: default$/: onprem/' -e "s#https://127.0.0.1:6443#https://${NODE_IP}:6443#" /etc/rancher/k3s/k3s.yaml > "$TMP"
if [[ -f ~/.kube/config ]]; then
  KUBECONFIG=~/.kube/config:"$TMP" kubectl config view --flatten > ~/.kube/config.new
  mv ~/.kube/config.new ~/.kube/config
else
  cp "$TMP" ~/.kube/config
fi
chmod 600 ~/.kube/config; rm -f "$TMP"
# kubectl wbudowany w k3s domyślnie czyta /etc/rancher/k3s/k3s.yaml – wskazujemy nasz plik
grep -q 'KUBECONFIG=~/.kube/config' ~/.bashrc || echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
export KUBECONFIG=~/.kube/config

kubectl --context onprem get nodes -o wide

log "Gotowe. Test z dowolnego klienta VPN:  curl -i http://${NODE_IP}   (oczekiwane: 404 z Traefika)"
