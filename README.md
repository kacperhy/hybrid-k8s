# Hybrydowe środowisko Kubernetes: k3s (lokalnie) + AKS (Azure)

Projekt z przedmiotu *Przetwarzanie w chmurze* — dwa współpracujące klastry Kubernetes,
wspólny sposób wdrażania (GitOps), wspólny rejestr obrazów, monitoring z wzajemnym
sprawdzaniem klastrów, automatyczne przełączanie ruchu i migracja usług z danymi.

**Całe środowisko jest dostępne wyłącznie przez VPN WireGuard** — nic nie jest wystawione
do internetu (poza API AKS ograniczonym do naszych adresów IP).

```
 Klient VPN (laptop, telefon)
        │ WireGuard
        ▼
 Raspberry Pi 10.10.20.1 ── HAProxy :8080  (health check /healthz co 2 s)
        │                     │ główny               │ backup
        │ WireGuard           ▼                      ▼
        │           VM k3s 10.10.20.6       bramka WireGuard w Azure (10.10.20.10 / 10.50.2.4)
        │           (VMware, Ubuntu)                 │ VNet 10.50.0.0/16
        │                                            ▼
        │                                  AKS, Traefik na wewnętrznym LB 10.50.1.250
        │
 ┌─ k3s ───────────────────────┐     ┌─ AKS ────────────────────────┐
 │ Traefik→frontend→api→redis  │     │ Traefik→frontend→api→redis   │
 │ Argo CD  Prometheus+Grafana │     │ Argo CD  Prometheus+Grafana  │
 │ blackbox ──sonda──────────────────► /healthz                     │
 │ /healthz ◄─────────────────────────sonda── blackbox              │
 │ Velero ──────┐              │     │ Velero ──────┐               │
 └──────────────│──────────────┘     └──────────────│───────────────┘
                └──────► Azure Blob "velero" ◄───────┘
 GitHub: repo (manifesty) ──pull──► oba Argo CD     GHCR: obrazy ──pull──► oba klastry
```

## Komponenty i uzasadnienie wyborów

| Wymaganie | Rozwiązanie | Dlaczego |
|---|---|---|
| Klaster lokalny | k3s na VM (VMware, Ubuntu), single-node | lekki, certyfikowany K8s, wbudowany Traefik i ServiceLB |
| Klaster w chmurze | AKS, Free tier, 1 węzeł, Ingress tylko na wewnętrznym LB | control plane bez opłat; brak publicznego wejścia do aplikacji |
| Łączność | WireGuard: Pi = hub, VM i bramka w Azure = peery (site-to-site do VNet) | jedna prywatna sieć dla obu lokalizacji, nic otwartego na routerze |
| Wspólne wdrażanie | Kustomize (base + overlay na klaster) + Argo CD w **każdym** klastrze | model pull: awaria jednego klastra nie blokuje wdrożeń na drugim |
| Obrazy kontenerów | GitHub Actions → GHCR, tag = SHA commita | ten sam, niezmienny obraz w obu lokalizacjach; CI sam podbija tag w Gicie |
| Monitoring | kube-prometheus-stack w obu klastrach + blackbox exporter | każdy klaster sonduje drugi (`PeerClusterDown`) i adres globalny; etykieta `cluster` |
| Kierowanie ruchu | Traefik (Ingress) w klastrach + **HAProxy na Pi** (onprem główny, AKS backup) | failover w ~4–6 s z health checkiem całego łańcucha frontend→api→redis |
| Przeniesienie usług | Velero + wspólny kontener Azure Blob | backup na jednym klastrze, restore na drugim, z danymi Redisa i zmianą klasy storage |
| Bezpieczeństwo | UFW + blokada portów aplikacji z LAN (`12-block-lan.sh`), API AKS tylko z naszych IP | k3s omija UFW regułami DNAT – filtrujemy wcześniej, w tabeli `mangle` |

Usługi (3): **frontend** (nginx + strona pokazująca, który klaster odpowiada), **api** (Flask,
`/api/info`, `/healthz`, `/metrics`), **redis** (StatefulSet z PVC — licznik odwiedzin jako stan do migracji).

## Adresy

| Co | Adres |
|---|---|
| Aplikacja (dla użytkowników) | http://10.10.20.1:8080 (HAProxy na Pi) |
| Panel HAProxy | http://10.10.20.1:8404 |
| Klaster onprem (Traefik) | http://10.10.20.6 |
| Klaster AKS (Traefik, wewnętrzny LB) | http://10.50.1.250 |
| Bramka Azure w VPN / w VNet | 10.10.20.10 / 10.50.2.4 |

## Struktura repo

```
app/                 kod usług + Dockerfile (api ma testy pytest)
deploy/base          wspólne manifesty aplikacji
deploy/overlays/     różnice per klaster (nazwa, kolor, repliki)
gitops/bootstrap/    app-of-apps (jedyna rzecz aplikowana ręcznie)
gitops/clusters/     Applications Argo CD dla każdego klastra
platform/            wartości Helm: monitoring, blackbox, Traefik (AKS), Velero; alerty + dashboard
infra/azure/         Terraform: VNet, bramka WireGuard, AKS, Storage na backupy
vpn/pi/              HAProxy i trasa do Azure na Raspberry Pi
vpn/vm/              trasa do Azure na VM z k3s
scripts/             instalacja i bootstrap krok po kroku
demo/                scenariusze: obserwacja ruchu, awarie, migracja
```

## Wdrożenie krok po kroku

1. **Konfiguracja i obrazy** — `cp config.env.example config.env`, `./scripts/01-configure.sh`, push.
   CI (`.github/workflows/build.yaml`) buduje obrazy do GHCR; pakiety ustaw jako **Public**.
2. **Klaster lokalny** (na VM): `./scripts/10-install-k3s.sh`, potem `sudo ./scripts/12-block-lan.sh`.
3. **GitOps na onprem**: `./scripts/30-bootstrap-cluster.sh onprem`.
4. **HAProxy na Pi** (skopiuj katalog `vpn/pi` na Pi): `sudo ./setup-haproxy.sh`.
5. **Azure**:
   1. Na Pi utwórz peera WireGuard `azure-gw` z adresem `10.10.20.10` (skrypt w `/etc/wireguard/clients`).
   2. `cp infra/azure/terraform.tfvars.example infra/azure/terraform.tfvars` — wpisz klucze z wygenerowanego `.conf`
      i swoje publiczne IP (`api_allowed_cidrs`).
   3. `./scripts/20-azure-infra.sh` — tworzy VNet, bramkę, AKS, Storage; pobiera kontekst `azure`.
   4. Na Pi: `sudo ./add-azure-route.sh <PublicKey bramki>`; na VM: `sudo ./vpn/vm/add-azure-route.sh`.
   5. `./scripts/30-bootstrap-cluster.sh azure`.
6. **Velero**: `./scripts/40-install-velero.sh onprem` i `./scripts/40-install-velero.sh azure`.
7. Sprawdzenie (z klienta VPN): `curl http://10.10.20.1:8080/api/info`, `curl http://10.50.1.250/api/info`.

Gdy zmieni się nasze publiczne IP (dostęp do API AKS):
`az aks update -g rg-hybryda -n aks-hybryda --api-server-authorized-ip-ranges <IP1>/32,<IP2>/32`.

## Scenariusze demonstracyjne

`./demo/watch.sh` uruchamiaj na maszynie w VPN, **która nie jest testowanym klastrem** (np. na Pi);
log CSV w `demo/logs/` posłuży do wykresu czasu przełączenia. Stan backendów widać też na http://10.10.20.1:8404.

| # | Scenariusz | Polecenie | Oczekiwany wynik |
|---|---|---|---|
| 1 | Awaria klastra lokalnego | `./demo/failover-onprem.sh down` | po ~4–6 s odpowiada `azure`; alert `PeerClusterDown` w Prometheusie w AKS |
| 1b | Powrót | `./demo/failover-onprem.sh up` | ruch wraca na `onprem` (HAProxy: onprem = główny) |
| 2 | Awaria chmury | `./demo/failover-azure.sh quick-down` / `full-down` | alert `PeerClusterDown` na onprem; użytkownicy nie odczuwają, bo onprem jest główny |
| 3 | Migracja z danymi | `./demo/migrate.sh` | licznik `visits` z onprem pojawia się w AKS, `cluster` nadal `azure` |
| 4 | Wdrożenie wersji w obu lokalizacjach | zmień np. tekst w `app/frontend/index.html`, push | CI buduje obraz, podbija tag, oba Argo CD wdrażają ten sam SHA |
| 5 | Self-healing | `kubectl --context onprem -n hybrid-app delete deploy api` | Argo CD odtwarza deployment w kilka sekund |

Ciekawe pytanie na obronę: dlaczego w scenariuszu 1 licznik w Azure jest inny niż na onprem?
Bo każdy klaster ma własnego Redisa — to architektura **active/passive bez replikacji danych**.
Scenariusz 3 pokazuje, jak przenieść stan planowo; ciągła replikacja to naturalne rozszerzenie.

Słaby punkt do omówienia: **Raspberry Pi** jest pojedynczym punktem awarii (VPN i HAProxy).
W produkcji: dwa huby z VRRP/keepalived albo zarządzana usługa (Azure VPN Gateway, Front Door).

## Koszty i oszczędzanie kredytu

Płatne: węzeł AKS (B2ms), bramka (B1s), publiczne IP bramki, Storage (grosze).
Gdy nie pracujesz: `az aks stop -g rg-hybryda -n aks-hybryda` i `az vm deallocate -g rg-hybryda -n vm-hybryda-gw`.
Po zaliczeniu: `cd infra/azure && terraform destroy`. Ustaw alert budżetowy w *Cost Management*.
Uwaga: `terraform.tfstate` zawiera klucz prywatny WireGuard bramki — nie commituj go (jest w `.gitignore`).

## Dostęp do paneli

Z Maximusa przez tunel SSH (panele działają tylko wewnątrz klastra):

```bash
ssh -L 8080:localhost:8080 -L 3000:localhost:3000 kacper@10.10.20.6
kubectl -n argocd port-forward svc/argocd-server 8080:80 &
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80 &   # dashboard "Hybrid K8s – przegląd"
```

## Wersje

Wersje chartów w `gitops/clusters/*` są ustawione zakresami (np. `75.*`). Przed startem sprawdź
najnowsze: `helm search repo <chart>` i dopasuj wersję pluginu Velero do wersji Velero
(tabela kompatybilności w repo `velero-plugin-for-microsoft-azure`).
