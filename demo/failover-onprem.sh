#!/usr/bin/env bash
# Scenariusz 1: awaria klastra lokalnego. Uruchom NA komputerze z k3s.
#   ./demo/failover-onprem.sh down   – zatrzymuje k3s i WSZYSTKIE kontenery (jak awaria zasilania)
#   ./demo/failover-onprem.sh up     – przywraca klaster
# W drugim terminalu: ./demo/watch.sh  -> po ~30-60 s odpowiada "azure",
# po "up" Traffic Manager (routing Priority) wraca na "onprem".
set -euo pipefail
case "${1:-}" in
  down) date +"%T awaria onprem: start"; sudo /usr/local/bin/k3s-killall.sh ;;
  up)   date +"%T przywracanie onprem"; sudo systemctl start k3s
        until kubectl --context onprem -n hybrid-app get pods 2>/dev/null | grep -q Running; do sleep 3; done
        kubectl --context onprem -n hybrid-app get pods ;;
  *) echo "użycie: $0 down|up"; exit 1 ;;
esac
