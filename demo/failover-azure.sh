#!/usr/bin/env bash
# Scenariusz 2: awaria klastra w chmurze (gdy to on obsługuje ruch, np. przy wyłączonym onprem,
# albo po zamianie priorytetów w Traffic Managerze).
#   ./demo/failover-azure.sh quick-down | quick-up   – wyłączenie Ingressu (sekundy)
#   ./demo/failover-azure.sh full-down  | full-up    – az aks stop/start (kilka minut, prawdziwe wyłączenie)
source "$(dirname "$0")/../scripts/lib.sh"
source "$(dirname "$0")/argo-pause.sh"
cd "$ROOT/infra/azure"
RG=$(terraform output -raw resource_group); AKS=$(terraform output -raw aks_name)
case "${1:-}" in
  quick-down) argo_pause azure traefik
              kubectl --context azure -n traefik scale deploy traefik --replicas=0 ;;
  quick-up)   argo_resume azure ;;
  full-down)  date +"%T az aks stop"; az aks stop -g "$RG" -n "$AKS" ;;
  full-up)    date +"%T az aks start"; az aks start -g "$RG" -n "$AKS" ;;
  *) echo "użycie: $0 quick-down|quick-up|full-down|full-up"; exit 1 ;;
esac
