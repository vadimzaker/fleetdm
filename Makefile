ROOT          := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
CLUSTER_NAME  := fleetdm-local
NAMESPACE     := fleetdm
RELEASE_NAME  := fleetdm
CHART_PATH    := $(ROOT)/charts/fleetdm
KIND_CONFIG   := $(ROOT)/kind-config.yaml

CERT_MANAGER_VERSION := v1.17.1

.PHONY: cluster install uninstall hosts status clean restore-db

## Create local Kind cluster with nginx ingress + cert-manager
cluster:
	@echo "==> Creating Kind cluster '$(CLUSTER_NAME)'..."
	kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG)
	@echo "==> Installing nginx ingress controller..."
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
	@echo "==> Installing cert-manager $(CERT_MANAGER_VERSION)..."
	kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/$(CERT_MANAGER_VERSION)/cert-manager.yaml
	@echo "==> Waiting 30s for pods to be scheduled..."
	sleep 30
	@echo "==> Waiting for nginx ingress controller..."
	kubectl wait --namespace ingress-nginx \
	  --for=condition=ready pod \
	  --selector=app.kubernetes.io/component=controller \
	  --timeout=120s
	@echo "==> Waiting for cert-manager webhook..."
	kubectl wait --namespace cert-manager \
	  --for=condition=ready pod \
	  --selector=app.kubernetes.io/component=webhook \
	  --timeout=120s
	@echo ""
	@echo "==> Cluster ready!"
	@echo "    Next: run 'make hosts' then 'make install'"

## Add fleet.local to /etc/hosts (requires sudo)
hosts:
	@grep -q "fleet.local" /etc/hosts && \
	  echo "fleet.local already in /etc/hosts" || \
	  (echo "127.0.0.1 fleet.local" | sudo tee -a /etc/hosts && echo "Added fleet.local → /etc/hosts")

## Install the FleetDM Helm chart
install:
	helm upgrade --install $(RELEASE_NAME) $(CHART_PATH) \
	  --namespace $(NAMESPACE) \
	  --create-namespace \
	  --wait \
	  --timeout 5m
	@echo ""
	@echo "==> FleetDM deployed!"
	@echo "    UI (HTTP):  http://fleet.local"
	@echo "    UI (HTTPS): https://fleet.local  (self-signed cert — accept browser warning)"
	@echo "    Direct:     http://localhost:8080 (NodePort for agents)"
	@echo ""
	@echo "    Fleet agent URL: http://localhost:8080"

## Uninstall the chart and delete the namespace
uninstall:
	helm uninstall $(RELEASE_NAME) --namespace $(NAMESPACE) || true
	kubectl delete namespace $(NAMESPACE) --ignore-not-found

## Restore the database from testdata/fleet-seed.sql.gz (for test environment)
restore-db:
	@echo "==> Waiting for MySQL to be ready..."
	kubectl wait --namespace $(NAMESPACE) \
	  --for=condition=ready pod \
	  --selector=app.kubernetes.io/component=mysql \
	  --timeout=120s
	@echo "==> Restoring fleet-seed.sql.gz..."
	kubectl cp $(ROOT)/testdata/fleet-seed.sql.gz \
	  $(NAMESPACE)/$(shell kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/component=mysql -o jsonpath='{.items[0].metadata.name}'):/tmp/fleet-seed.sql.gz
	kubectl exec -n $(NAMESPACE) \
	  $(shell kubectl get pod -n $(NAMESPACE) -l app.kubernetes.io/component=mysql -o jsonpath='{.items[0].metadata.name}') -- \
	  sh -c "gunzip -c /tmp/fleet-seed.sql.gz | mysql -u fleet -pfleetpassword fleet"
	@echo "==> Restarting Fleet to pick up restored data..."
	kubectl rollout restart deployment/$(RELEASE_NAME)-fleetdm -n $(NAMESPACE)
	kubectl rollout status deployment/$(RELEASE_NAME)-fleetdm -n $(NAMESPACE)
	@echo "==> Done! Test data restored."

## Delete the local cluster entirely
clean:
	kind delete cluster --name $(CLUSTER_NAME)


## Show pod and service status + Fleet health
status:
	@echo "--- Pods ---"
	kubectl get pods -n $(NAMESPACE)
	@echo "--- Services ---"
	kubectl get svc -n $(NAMESPACE)
	@echo "--- Ingress ---"
	kubectl get ingress -n $(NAMESPACE)
	@echo "--- TLS Certificate ---"
	kubectl get certificate -n $(NAMESPACE) 2>/dev/null || echo "(cert-manager not installed)"
