# FleetDM Helm Chart

Deploys [FleetDM](https://fleetdm.com/) — with MySQL and Redis on a local Kubernetes cluster (Kind).

## Prerequisites

| Tool | Version |
|---|---|
| Docker | 24+ |
| Kind | 0.22+ |
| kubectl | 1.29+ |
| Helm | 3.14+ |

**macOS:**
```bash
brew install kind kubectl helm
```

**Linux (Ubuntu / Debian):**
```bash
# Docker
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker $USER && newgrp docker

# Kind
curl -Lo /usr/local/bin/kind \
  "https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64"
chmod +x /usr/local/bin/kind

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

---

## Quick Start

### 1. Create local cluster

```bash
make cluster
```

Creates a Kind cluster and installs:
- nginx ingress controller (port 80 and 443)
- cert-manager (for automatic TLS certificate generation)

### 2. Register fleet.local in /etc/hosts

```bash
make hosts
# equivalent to:
echo "127.0.0.1 fleet.local" | sudo tee -a /etc/hosts
```

> **Linux/macOS** — requires `sudo`. On Windows: add `127.0.0.1 fleet.local` to `C:\Windows\System32\drivers\etc\hosts` manually.

### 3. Install FleetDM

```bash
make install
```

This command:
- Deploys FleetDM, MySQL, Redis to the `fleetdm` namespace
- Automatically runs `fleet prepare db` as a post-install Helm hook
- Creates a self-signed TLS certificate via cert-manager

### 4. Access the UI

| URL | Description |
|---|---|
| **https://fleet.local** | HTTPS via Ingress (recommended) |
| http://fleet.local | HTTP via Ingress |
| http://localhost:8080 | Direct NodePort (for agents) |

> **Browser warning:** the certificate is self-signed. Click "Advanced → Proceed" to continue.

### 5. Test database (optional)

Restore the included seed database with a pre-configured admin account:

```bash
make restore-db
```

| Field | Value |
|---|---|
| **URL** | http://fleet.local |
| **Email** | `test@test.com` |
| **Password** | `9d1>J;YW8%nm3` |

> The seed dump is stored in `testdata/fleet-seed.sql.gz` and includes sample hosts, labels, enroll secrets and osquery configuration.

---


## Verification

### Check all pods are running

```bash
make status
# or
kubectl get pods -n fleetdm
```

Expected output:
```
NAME                              READY   STATUS      RESTARTS
fleetdm-fleetdm-xxx               1/1     Running     0
fleetdm-mysql-0                   1/1     Running     0
fleetdm-redis-master-0            1/1     Running     0
fleetdm-fleetdm-prepare-db-xxx    0/1     Completed   0
```

### Verify MySQL is operational

```bash
kubectl exec -n fleetdm -it fleetdm-mysql-0 -- \
  mysql -u fleet -pfleetpassword fleet -e "SHOW TABLES;"
```

### Verify Redis is operational

```bash
kubectl exec -n fleetdm -it fleetdm-redis-master-0 -- \
  redis-cli ping
# Expected: PONG
```

### Verify FleetDM health endpoint

```bash
kubectl exec -n fleetdm \
  deploy/fleetdm-fleetdm -- \
  wget -qO- http://localhost:8080/healthz
# Expected: {"healthy":true}
```

---

## Teardown

Remove chart and namespace:
```bash
make uninstall
```

Delete the cluster entirely:
```bash
make clean
```

---

## Configuration

Override values via `--set` or a custom `values.yaml`:

```bash
helm upgrade --install fleetdm ./charts/fleetdm \
  --namespace fleetdm --create-namespace \
  --set fleet.secrets.jwtKey="your-secure-key-here" \
  --set fleet.ingress.host="myfleet.example.com"
```


---

## CI

On **push to `main`**: chart lint + **chart-releaser** (uploads `.tgz` to GitHub Releases, updates `gh-pages` for the Helm repo index).

A new release is created only if the chart changed and **`version`** in `charts/fleetdm/Chart.yaml` was bumped.

Install from a release: download the `.tgz` from **Releases** or pass its URL to `helm install`.

**Helm repo** (requires GitHub Pages + `index.yaml` on `gh-pages`):

```bash
helm repo add fleetdm https://vadimzaker.github.io/fleetdm
helm repo update
helm install fleetdm fleetdm/fleetdm
```
