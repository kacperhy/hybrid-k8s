#!/usr/bin/env bash
# Co pół sekundy odpytuje aplikację przez HAProxy na Pi i pokazuje, który klaster odpowiada.
# Wynik zapisuje do demo/logs/*.csv – z niego liczymy czas przełączenia do sprawozdania.
#   ./demo/watch.sh                      (domyślnie APP_URL z config.env, czyli http://10.10.20.1)
#   ./demo/watch.sh http://10.10.20.6    (bezpośrednio jeden klaster, z pominięciem HAProxy)
source "$(dirname "$0")/../scripts/lib.sh"
load_config
need curl jq
URL="${1:-$APP_URL}"
INTERVAL="${INTERVAL:-0.5}"
mkdir -p "$ROOT/demo/logs"
LOG="$ROOT/demo/logs/watch-$(date +%Y%m%d-%H%M%S).csv"
echo "time,cluster,pod,visits,http_ms" > "$LOG"
log "Obserwuję $URL co ${INTERVAL}s  (log: ${LOG#$ROOT/})"
while true; do
  ts=$(date +%T.%3N)
  start=$(date +%s%3N)
  if body=$(curl -fsS -m 2 "$URL/api/info" 2>/dev/null); then
    ms=$(( $(date +%s%3N) - start ))
    read -r cl pod vis < <(jq -r '"\(.cluster) \(.pod) \(.visits)"' <<<"$body")
    printf '%s  %-7s %-28s visits=%-6s %5sms\n' "$ts" "$cl" "$pod" "$vis" "$ms"
    echo "$ts,$cl,$pod,$vis,$ms" >> "$LOG"
  else
    printf '%s  \033[31mBRAK ODPOWIEDZI\033[0m\n' "$ts"
    echo "$ts,DOWN,,," >> "$LOG"
  fi
  sleep "$INTERVAL"
done
