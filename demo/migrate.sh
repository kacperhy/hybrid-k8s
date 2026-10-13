#!/usr/bin/env bash
# Scenariusz 3: przeniesienie usług RAZEM Z DANYMI z onprem do Azure (Velero).
# Licznik odwiedzin z Redisa na onprem pojawia się w AKS. Konfiguracja specyficzna
# dla klastra (ConfigMap cluster-info) wraca do wartości "azure" dzięki Argo CD –
# przenosimy stan, a nie tożsamość środowiska.
#   ./demo/migrate.sh            (onprem -> azure)
#   ./demo/migrate.sh azure onprem
source "$(dirname "$0")/../scripts/lib.sh"
source "$(dirname "$0")/argo-pause.sh"
load_config
need velero kubectl curl jq
SRC="${1:-onprem}"; DST="${2:-azure}"
NAME="mig-${SRC}-to-${DST}-$(date +%H%M%S)"

log "[$SRC] stan przed migracją"
kubectl --context "$SRC" -n hybrid-app exec sts/redis -- redis-cli get visits

log "[$SRC] backup $NAME (manifesty + dane wolumenu Redisa)"
velero --kubecontext "$SRC" backup create "$NAME" --include-namespaces hybrid-app --wait
velero --kubecontext "$SRC" backup describe "$NAME" | grep -E 'Phase|Items backed up|Pod Volume'

log "[$DST] czekam, aż backup będzie widoczny w drugim klastrze"
until velero --kubecontext "$DST" backup get "$NAME" 2>/dev/null | grep -q Completed; do sleep 5; done

log "[$DST] wstrzymuję Argo CD i usuwam bieżącą instancję aplikacji"
argo_pause "$DST" hybrid-app
kubectl --context "$DST" delete namespace hybrid-app --wait=true

log "[$DST] odtwarzam z backupu"
velero --kubecontext "$DST" restore create "${NAME}-restore" --from-backup "$NAME" --wait
velero --kubecontext "$DST" restore describe "${NAME}-restore" | grep -E 'Phase|Warnings|Errors'

argo_resume "$DST"
kubectl --context "$DST" -n hybrid-app rollout status deploy/api --timeout=180s

log "[$DST] stan po migracji"
kubectl --context "$DST" -n hybrid-app exec sts/redis -- redis-cli get visits
[[ "$DST" == azure ]] && curl -s "http://${AKS_INGRESS_FQDN}/api/info" | jq . || true
