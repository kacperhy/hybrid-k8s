#!/usr/bin/env bash
# Podstawia wartości z config.env w miejsce placeholderów w manifestach.
# Uruchom raz po sklonowaniu repo, a potem zacommituj zmiany (Argo CD czyta z Gita!).
source "$(dirname "$0")/lib.sh"
load_config

files=$(grep -rlE 'GITHUB_USER|GIT_REPO_URL|AKS_DNS_LABEL|AKS_INGRESS_FQDN|DOMAIN' \
  "$ROOT/deploy" "$ROOT/gitops" "$ROOT/platform" || true)

for f in $files; do
  sed -i \
    -e "s#GIT_REPO_URL#${GIT_REPO_URL}#g" \
    -e "s#ghcr.io/GITHUB_USER#ghcr.io/${GITHUB_USER,,}#g" \
    -e "s#AKS_INGRESS_FQDN#${AKS_INGRESS_FQDN}#g" \
    -e "s#AKS_DNS_LABEL#${AKS_DNS_LABEL}#g" \
    -e "s#app\.DOMAIN#app.${DOMAIN}#g" \
    -e "s#onprem\.DOMAIN#onprem.${DOMAIN}#g" \
    "$f"
  echo "  zaktualizowano: ${f#$ROOT/}"
done
log "Gotowe. Teraz: git add -A && git commit -m 'konfiguracja' && git push"
