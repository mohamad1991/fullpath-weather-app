# One entry point for humans. CI calls the same targets, so "works on my machine"
# and "works in CI" mean the same thing.
SHELL      := /bin/bash
export PATH := $(CURDIR)/.bin:$(PATH)
CLUSTER    ?= weather
TAG        ?= dev
LOCAL_ENV  := infra/environments/local
CHART      := deploy/charts/weather
KCTX       := kind-$(CLUSTER)

.PHONY: help
help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

# --- Inner loop ---------------------------------------------------------------------
.PHONY: dev
dev: ## Run the app with docker compose (http://localhost:8080)
	docker compose up --build

.PHONY: test
test: ## Lint + unit/integration tests (needs `docker compose up -d db`)
	. .venv/bin/activate && ruff check apps/ && ruff format --check apps/
	. .venv/bin/activate && cd apps/collector && python -m pytest -q
	. .venv/bin/activate && cd apps/api && DB_PORT=55432 DB_PASSWORD=weather-local-only DB_SSLMODE=disable python -m pytest -q
	cd apps/frontend && npm test

# --- Local Kubernetes (kind, provisioned by Terraform) --------------------------------
.PHONY: local-up
local-up: ## Create kind cluster + platform (Traefik, CNPG, metrics-server, Postgres)
	terraform -chdir=$(LOCAL_ENV) init -input=false
	terraform -chdir=$(LOCAL_ENV) apply -input=false -auto-approve

.PHONY: local-images
local-images: ## Build images and load them into kind
	for c in api collector frontend; do \
	  docker build -t weather/$$c:$(TAG) apps/$$c && kind load docker-image weather/$$c:$(TAG) --name $(CLUSTER); \
	done

.PHONY: local-deploy
local-deploy: local-images ## Helm-deploy the app to kind (Argo CD replaces this in Phase 4)
	helm --kube-context $(KCTX) upgrade --install weather $(CHART) -n weather \
	  -f $(CHART)/ci/local-values.yaml --set image.tag=$(TAG) --wait --timeout 5m
	@echo "App: http://localhost:8088"

.PHONY: local-verify
local-verify: ## Prove NetworkPolicies are enforced
	kubectl config use-context $(KCTX) >/dev/null && scripts/verify-netpol.sh

.PHONY: local-down
local-down: ## Destroy the local cluster
	terraform -chdir=$(LOCAL_ENV) destroy -input=false -auto-approve

# --- Static checks (same as CI) --------------------------------------------------------
.PHONY: lint-infra
lint-infra: ## terraform fmt/validate + helm lint + checkov
	terraform fmt -check -recursive infra
	for d in infra/bootstrap infra/global infra/environments/*/; do \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d validate || exit 1; \
	done
	helm lint $(CHART) -f $(CHART)/ci/local-values.yaml --strict
	helm lint $(CHART) -f $(CHART)/ci/aws-values.yaml --strict
	. .venv/bin/activate && checkov -d infra --framework terraform --quiet --compact --skip-download --skip-path '\.terraform'
