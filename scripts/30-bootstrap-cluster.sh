#!/usr/bin/env bash
# Instaluje Argo CD w podanym klastrze i aplikuje app-of-apps.
# Od tej chwili wszystko (aplikacja, monitoring, Traefik w AKS) zarządza Argo CD z Gita.
#   ./scripts/30-bootstrap-cluster.sh onprem
#   ./scripts/30-bootstrap-cluster.sh azure
source "$(dirname "$0")/lib.sh"
need kubectl helm
CTX="${1:?Podaj kontekst: onprem | azure}"
K="kubectl --context $CTX"

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null

log "[$CTX] Argo CD"
helm --kube-context "$CTX" upgrade --install argocd argo/argo-cd \
  -n argocd --create-namespace --version '^8.0.0' \
  --set 'configs.params.server\.insecure=true' \
  --set dex.enabled=false \
  --set notifications.enabled=false \
  --set applicationSet.replicas=1 \
  --wait

log "[$CTX] Sekret z hasłem do Grafany"
$K create namespace monitoring --dry-run=client -o yaml | $K apply -f -
if ! $K -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  PASS=$(openssl rand -base64 18)
  $K -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin --from-literal=admin-password="$PASS"
  echo "  Grafana [$CTX]: admin / $PASS   (zapisz!)"
fi

log "[$CTX] App-of-apps"
$K apply -f "$ROOT/gitops/bootstrap/root-$CTX.yaml"

echo
echo "Hasło do Argo CD (admin):"
$K -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
echo "UI:  kubectl --context $CTX -n argocd port-forward svc/argocd-server 8080:80"
echo "     kubectl --context $CTX -n monitoring port-forward svc/monitoring-grafana 3000:80"
