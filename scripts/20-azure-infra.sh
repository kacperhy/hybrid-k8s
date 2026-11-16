#!/usr/bin/env bash
# Tworzy w Azure: VNet, bramkę WireGuard, AKS (Ingress tylko wewnętrzny) i storage
# na backupy (Terraform), a potem pobiera kubeconfig jako kontekst 'azure'.
source "$(dirname "$0")/lib.sh"
need az terraform kubectl
cd "$ROOT/infra/azure"
[[ -f terraform.tfvars ]] || die "Skopiuj infra/azure/terraform.tfvars.example -> terraform.tfvars i uzupełnij"

az account show >/dev/null 2>&1 || az login
terraform init -upgrade
terraform apply

RG=$(terraform output -raw resource_group)
AKS=$(terraform output -raw aks_name)
log "Pobieram poświadczenia AKS jako kontekst 'azure'"
az aks get-credentials -g "$RG" -n "$AKS" --context azure --overwrite-existing
kubectl --context azure get nodes -o wide

log "Dalej:"
echo "  1. Na Pi:  sudo ./vpn/pi/add-azure-route.sh <PublicKey bramki> $(terraform output -raw vnet_cidr)"
echo "  2. Na VM:  sudo ./vpn/vm/add-azure-route.sh $(terraform output -raw vnet_cidr)"
echo "  3. Tunel:   ssh azureuser@$(terraform output -raw gw_public_ip) 'sudo wg show'   (ma być 'latest handshake')"
echo "  4. ./scripts/30-bootstrap-cluster.sh azure"
echo "  5. Test z klienta VPN:  curl http://$(terraform output -raw aks_ingress_ip)/api/info"
