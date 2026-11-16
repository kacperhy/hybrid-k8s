#!/usr/bin/env bash
# Instaluje Velero w podanym klastrze. Oba klastry używają TEGO SAMEGO kontenera
# w Azure Blob Storage, więc backup zrobiony na onprem jest widoczny w AKS (i odwrotnie).
#   ./scripts/40-install-velero.sh onprem
#   ./scripts/40-install-velero.sh azure
source "$(dirname "$0")/lib.sh"
need kubectl helm terraform
CTX="${1:?Podaj kontekst: onprem | azure}"

cd "$ROOT/infra/azure"
RG=$(terraform output -raw resource_group)
SA=$(terraform output -raw velero_storage_account)
KEY=$(terraform output -raw velero_storage_key)
SUB=$(terraform output -raw subscription_id)
cd "$ROOT"

helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts >/dev/null
helm repo update vmware-tanzu >/dev/null

CREDS=$(mktemp); trap 'rm -f $CREDS' EXIT
cat > "$CREDS" <<CRED
AZURE_STORAGE_ACCOUNT_ACCESS_KEY=${KEY}
AZURE_CLOUD_NAME=AzurePublicCloud
CRED

log "[$CTX] Velero"
helm --kube-context "$CTX" upgrade --install velero vmware-tanzu/velero \
  -n velero --create-namespace --version '^10.0.0' \
  -f "$ROOT/platform/velero/values.yaml" \
  --set-file credentials.secretContents.cloud="$CREDS" \
  --set "configuration.backupStorageLocation[0].config.resourceGroup=$RG" \
  --set "configuration.backupStorageLocation[0].config.storageAccount=$SA" \
  --set "configuration.backupStorageLocation[0].config.subscriptionId=$SUB" \
  --wait

# Przy odtwarzaniu backupu z DRUGIEGO klastra zamieniamy klasy storage:
# k3s "local-path" <-> AKS "default"/"managed-csi" (Azure Disk CSI).
if [[ "$CTX" == "azure" ]]; then MAP=$'  local-path: default'; else MAP=$'  default: local-path\n  managed-csi: local-path'; fi
kubectl --context "$CTX" apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: change-storage-class-config
  namespace: velero
  labels:
    velero.io/plugin-config: ""
    velero.io/change-storage-class: RestoreItemAction
data:
$(printf '%b' "$MAP")
YAML
kubectl --context "$CTX" -n velero get backupstoragelocations
