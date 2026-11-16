#!/usr/bin/env bash
# Dodaje sieć Azure (VNet) do peera bramki WireGuard na Pi i ustawia trasę.
# Najpierw utwórz peera bramki swoim skryptem z /etc/wireguard/clients (np. nazwa "azure-gw",
# adres 10.10.20.10), a potem uruchom NA PI jako root:
#   sudo ./add-azure-route.sh <PublicKey bramki> [10.50.0.0/16]
set -euo pipefail
GW_PUB="${1:?Podaj klucz publiczny bramki (wg show wg0 | grep -B1 10.10.20.10)}"
VNET="${2:-10.50.0.0/16}"

CURRENT=$(wg show wg0 allowed-ips | awk -v k="$GW_PUB" '$1==k {$1=""; print}' | xargs | tr ' ' ',')
[[ -n "$CURRENT" ]] || { echo "Nie znalazłem peera z tym kluczem w wg0"; exit 1; }
case ",$CURRENT," in *",$VNET,"*) ;; *) CURRENT="$CURRENT,$VNET" ;; esac

wg set wg0 peer "$GW_PUB" allowed-ips "$CURRENT"
ip route replace "$VNET" dev wg0
wg-quick save wg0      # utrwala AllowedIPs (wg-quick przy starcie sam doda trasę)

# ruch między peerami przez Pi (klient VPN -> bramka Azure) – jeśli reguły jeszcze nie ma
ufw status | grep -q "ALLOW FWD.*on wg0" || ufw route allow in on wg0 out on wg0

echo "Peer bramki: allowed-ips = $CURRENT"
ip route get "${VNET%/*}" | head -1
