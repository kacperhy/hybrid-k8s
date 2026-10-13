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
  AKS_INGRESS_FQDN="${AKS_DNS_LABEL}.${LOCATION}.cloudapp.azure.com"
}
