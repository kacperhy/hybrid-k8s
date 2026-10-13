# Hybrydowe środowisko Kubernetes: k3s (lokalnie) + AKS (Azure)

Projekt z przedmiotu *Przetwarzanie w chmurze* — dwa współpracujące klastry Kubernetes,
wspólny sposób wdrażania (GitOps), wspólny rejestr obrazów, monitoring z wzajemnym
sprawdzaniem klastrów, automatyczne przełączanie ruchu i migracja usług z danymi.

```
                       użytkownik ──► app.serwerfrajerow.top (CNAME)
                                              │
                                 Azure Traffic Manager (Priority, sonda /healthz co 10 s)
                                 ┌────────────┴─────────────┐
                        priorytet 1                    priorytet 2
                onprem.serwerfrajerow.top        <label>.<region>.cloudapp.azure.com
                (router: port 80 → PC)            (Azure Load Balancer)
                          │                                   │
             ┌─ k3s (PC z Ubuntu) ─────────┐     ┌─ AKS (1 węzeł B2ms) ─────────┐
             │ Traefik→frontend→api→redis  │     │ Traefik→frontend→api→redis   │
             │ Argo CD   Prometheus+Grafana │     │ Argo CD   Prometheus+Grafana │
             │ blackbox ──sonda──────────────────────► /healthz                  │
             │ /healthz ◄──────────────────────sonda── blackbox                 │
             │ Velero ───────┐              │     │ Velero ───────┐              │
             └───────────────│──────────────┘     └───────────────│──────────────┘
                             └──────► Azure Blob "velero" ◄────────┘
     GitHub: repo (manifesty) ──pull──► oba Argo CD      GHCR: obrazy ──pull──► oba klastry
```

## Komponenty i uzasadnienie wyborów

| Wymaganie | Rozwiązanie | Dlaczego |
|---|---|---|
| Klaster lokalny | k3s na Ubuntu (single-node) | lekki, certyfikowany K8s, wbudowany Traefik i ServiceLB |
| Klaster w chmurze | AKS, Free tier, 1 węzeł | control plane bez opłat, płacimy tylko za węzeł; można go zatrzymać (`az aks stop`) |
| Wspólne wdrażanie | Kustomize (base + overlay na klaster) + Argo CD w **każdym** klastrze | model pull: awaria jednego klastra nie blokuje wdrożeń na drugim |
| Obrazy kontenerów | GitHub Actions → GHCR, tag = SHA commita | ten sam, niezmienny obraz w obu lokalizacjach; CI sam podbija tag w Gicie |
| Monitoring | kube-prometheus-stack w obu klastrach + blackbox exporter | każdy klaster sonduje drugi (`PeerClusterDown`) i adres globalny; etykieta `cluster` |
| Kierowanie ruchu | Traefik (Ingress) lokalnie + Azure Traffic Manager globalnie | failover DNS z health checkiem całego łańcucha frontend→api→redis |
| Przeniesienie usług | Velero + wspólny kontener Azure Blob | backup na jednym klastrze, restore na drugim, z danymi Redisa i zmianą klasy storage |

Usługi (3): **frontend** (nginx + strona pokazująca, który klaster odpowiada), **api** (Flask,
`/api/info`, `/healthz`, `/metrics`), **redis** (StatefulSet z PVC — licznik odwiedzin jako stan do migracji).

## Struktura repo

```
app/                 kod usług + Dockerfile (api ma testy pytest)
deploy/base          wspólne manifesty aplikacji
deploy/overlays/     różnice per klaster (nazwa, kolor, repliki)
gitops/bootstrap/    app-of-apps (jedyna rzecz aplikowana ręcznie)
gitops/clusters/     Applications Argo CD dla każdego klastra
platform/            wartości Helm: monitoring, blackbox, Traefik (AKS), Velero; alerty + dashboard
infra/azure/         Terraform: AKS, Traffic Manager, Storage na backupy
scripts/             instalacja i bootstrap krok po kroku
demo/                scenariusze: obserwacja ruchu, awarie, migracja
```

## Wymagania wstępne

- PC z Ubuntu (≥ 4 GB RAM wolne, najlepiej 8), publiczne IP w domu (bez CGNAT), dostęp do routera.
- Konto **Azure for Students**. Sprawdź dozwolone regiony: *Azure Policy → Assignments →
  Allowed resource deployment regions* i ustaw jeden z nich jako `location`.
- Narzędzia na maszynie, z której zarządzasz: `az`, `terraform`, `kubectl`, `helm`, `velero`, `jq`, `dig`.
- Repo na GitHubie (publiczne albo dodaj repo w Argo CD z tokenem).

## Wdrożenie krok po kroku

1. **Konfiguracja**
   ```bash
   cp config.env.example config.env            # uzupełnij
   cp infra/azure/terraform.tfvars.example infra/azure/terraform.tfvars
   ./scripts/01-configure.sh
   git add -A && git commit -m "konfiguracja" && git push
   ```
2. **Obrazy** — push do `main` uruchamia `.github/workflows/build.yaml`. Po pierwszym
   buildzie ustaw w GitHub → Packages widoczność `hybrid-api` i `hybrid-frontend` na **Public**
   (inaczej klastry potrzebują `imagePullSecret`).
3. **Klaster lokalny** (na PC): `./scripts/10-install-k3s.sh`, potem przekierowanie portów
   80/443 na routerze i rekord `onprem.<domena>` w DDNS.
4. **Azure**: `./scripts/20-azure-infra.sh`, potem w Spaceship: `CNAME app → tm-<prefix>.trafficmanager.net`.
5. **GitOps w obu klastrach**:
   ```bash
   ./scripts/30-bootstrap-cluster.sh onprem
   ./scripts/30-bootstrap-cluster.sh azure
   ```
   Argo CD instaluje monitoring, blackbox, (w AKS) Traefika, a na końcu aplikację.
6. **Velero**: `./scripts/40-install-velero.sh onprem` i `./scripts/40-install-velero.sh azure`.
7. Sprawdzenie: `curl http://app.<domena>/api/info`, `kubectl --context azure -n hybrid-app get pods`.

## Scenariusze demonstracyjne

Terminal 1 zawsze: `./demo/watch.sh` (log CSV w `demo/logs/` do wykresu w sprawozdaniu).

> **Uwaga — hairpin NAT:** jeśli uruchamiasz `watch.sh` z sieci domowej, część routerów
> nie obsłuży połączenia na własne publiczne IP. Puść go z telefonu na hotspocie,
> z Azure Cloud Shell albo z innej sieci.

| # | Scenariusz | Polecenie | Oczekiwany wynik |
|---|---|---|---|
| 1 | Awaria klastra lokalnego | `./demo/failover-onprem.sh down` | po ~30–60 s odpowiada `azure`; alert `PeerClusterDown` w Prometheusie w AKS |
| 1b | Powrót | `./demo/failover-onprem.sh up` | ruch wraca na `onprem` (routing Priority) |
| 2 | Awaria chmury | `./demo/failover-azure.sh quick-down` / `full-down` | alert `PeerClusterDown` na onprem; użytkownicy nie odczuwają, bo onprem jest główny |
| 3 | Migracja z danymi | `./demo/migrate.sh` | licznik `visits` z onprem pojawia się w AKS, `cluster` nadal `azure` |
| 4 | Wdrożenie wersji w obu lokalizacjach | zmień np. tekst w `app/frontend/index.html`, push | CI buduje obraz, podbija tag, oba Argo CD wdrażają ten sam SHA |
| 5 | Self-healing | `kubectl --context onprem -n hybrid-app delete deploy api` | Argo CD odtwarza deployment w kilka sekund |

Ciekawe pytanie na obronę: dlaczego w scenariuszu 1 licznik w Azure jest inny niż na onprem?
Bo każdy klaster ma własnego Redisa — to architektura **active/passive bez replikacji danych**.
Scenariusz 3 pokazuje, jak przenieść stan planowo; ciągła replikacja (np. Redis z replicą przez VPN)
to naturalne rozszerzenie.

## Koszty i oszczędzanie kredytu

Płatne są głównie: węzeł AKS, publiczne IP Load Balancera, Traffic Manager (grosze), Storage (grosze).
Gdy nie pracujesz: `az aks stop -g rg-hybryda -n aks-hybryda` (węzły nie są naliczane).
Po zaliczeniu: `cd infra/azure && terraform destroy`. Ustaw alert budżetowy w *Cost Management*.

## Dostęp do paneli

```bash
kubectl --context onprem -n argocd port-forward svc/argocd-server 8080:80
kubectl --context onprem -n monitoring port-forward svc/monitoring-grafana 3000:80   # dashboard "Hybrid K8s – przegląd"
kubectl --context azure  -n monitoring port-forward svc/monitoring-prometheus 9090:9090
```

## Wersje

Wersje chartów w `gitops/clusters/*` są ustawione zakresami (np. `75.*`). Przed startem sprawdź
najnowsze: `helm search repo <chart>` i dopasuj wersję pluginu Velero do wersji Velero
(tabela kompatybilności w repo `velero-plugin-for-microsoft-azure`).
