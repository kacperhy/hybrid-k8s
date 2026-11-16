# Wstrzymanie / wznowienie auto-synchronizacji Argo CD (root + wskazana aplikacja).
# Potrzebne, gdy celowo psujemy coś, co Argo CD (selfHeal) natychmiast by naprawiło.
argo_pause() { # ctx app
  kubectl --context "$1" -n argocd patch app root --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null
  kubectl --context "$1" -n argocd patch app "$2" --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null
  echo "Argo CD [$1]: auto-sync wstrzymany (root, $2)"
}
argo_resume() { # ctx
  kubectl --context "$1" -n argocd patch app root --type merge \
    -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' >/dev/null
  echo "Argo CD [$1]: auto-sync wznowiony – root przywróci stan z Gita"
}
