#!/usr/bin/env bash
# Tworzy AKS, Traffic Manager i storage na backupy (Terraform), pobiera kubeconfig.
source "$(dirname "$0")/lib.sh"
need az terraform kubectl
cd "$ROOT/infra/azure"
[[ -f terraform.tfvars ]] || die "Skopiuj infra/azure/terraform.tfvars.example -> terraform.tfvars"

az account show >/dev/null 2>&1 || az login
terraform init -upgrade
terraform apply

RG=$(terraform output -raw resource_group)
AKS=$(terraform output -raw aks_name)
log "Pobieram poświadczenia AKS jako kontekst 'azure'"
az aks get-credentials -g "$RG" -n "$AKS" --context azure --overwrite-existing
kubectl --context azure get nodes -o wide

log "Ustaw w DNS (Spaceship):  CNAME  app  ->  $(terraform output -raw traffic_manager_fqdn)"
