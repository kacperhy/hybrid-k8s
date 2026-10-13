#!/usr/bin/env bash
# Co sekundę odpytuje globalny adres aplikacji i pokazuje, który klaster odpowiada.
# Wynik zapisuje do demo/logs/*.csv – przyda się do wykresu czasu przełączenia w sprawozdaniu.
source "$(dirname "$0")/../scripts/lib.sh"
load_config
need curl jq dig
HOST="${1:-app.${DOMAIN}}"
mkdir -p "$ROOT/demo/logs"
LOG="$ROOT/demo/logs/watch-$(date +%Y%m%d-%H%M%S).csv"
echo "time,resolved,cluster,pod,visits,http_ms" > "$LOG"
log "Obserwuję http://$HOST  (log: ${LOG#$ROOT/})"
while true; do
  ts=$(date +%T)
  target=$(dig +short "$HOST" | grep -v '^[0-9.]*$' | tail -1)   # CNAME z Traffic Managera
  [[ -z "$target" ]] && target=$(dig +short "$HOST" | tail -1)
  start=$(date +%s%3N)
  if body=$(curl -fsS -m 3 "http://$HOST/api/info" 2>/dev/null); then
    ms=$(( $(date +%s%3N) - start ))
    read -r cl pod vis < <(jq -r '"\(.cluster) \(.pod) \(.visits)"' <<<"$body")
    printf '%s  %-45s  %-7s %-28s visits=%-6s %5sms\n' "$ts" "$target" "$cl" "$pod" "$vis" "$ms"
    echo "$ts,$target,$cl,$pod,$vis,$ms" >> "$LOG"
  else
    printf '%s  %-45s  \033[31mBRAK ODPOWIEDZI\033[0m\n' "$ts" "$target"
    echo "$ts,$target,DOWN,,," >> "$LOG"
  fi
  sleep 1
done
