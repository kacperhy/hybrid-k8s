# Wspólne funkcje skryptów.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log()  { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*"; exit 1; }
need() { for b in "$@"; do command -v "$b" >/dev/null || die "Brak narzędzia: $b"; done; }
load_config() {
  [[ -f "$ROOT/config.env" ]] || die "Brak config.env – skopiuj config.env.example"
  # shellcheck disable=SC1091
  source "$ROOT/config.env"
  # adresy w sieci VPN (wartości domyślne, jeśli config.env ich nie ma)
  APP_URL="${APP_URL:-http://10.10.20.1}"            # HAProxy na Raspberry Pi
  ONPREM_INGRESS_IP="${ONPREM_INGRESS_IP:-10.10.20.6}"
  AZURE_INGRESS_IP="${AZURE_INGRESS_IP:-10.50.1.250}"
}
