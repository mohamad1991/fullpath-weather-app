# One entry point for humans. CI calls the same targets, so "works on my machine"
# and "works in CI" mean the same thing.
SHELL      := /bin/bash
export PATH := $(CURDIR)/.bin:$(PATH)
# Resolve tools to absolute paths once. Make runs simple one-line recipes WITHOUT a
# shell, using its original PATH - so the export above alone would silently pick
# e.g. an old Homebrew terraform instead of the pinned one in .bin/.
which_tool = $(firstword $(wildcard $(CURDIR)/.bin/$(1)) $(shell command -v $(1)))
TERRAFORM  := $(call which_tool,terraform)
KUBECTL    := $(call which_tool,kubectl)
PROMTOOL   := $(call which_tool,promtool)
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

.PHONY: venv
venv: ## Create .venv with hash-locked deps
	python3 -m venv .venv
	. .venv/bin/activate && for c in api collector; do \
	  pip install -q --require-hashes -r apps/$$c/requirements.txt -r apps/$$c/requirements-dev.txt || exit 1; \
	done
	# Tools get their own venv: checkov's pins would otherwise fight the app's lock file.
	python3 -m venv .venv-tools && .venv-tools/bin/pip install -q checkov==3.3.30

.PHONY: lock
lock: ## Re-compile hashed lock files from requirements*.in (in python:3.12, matching the runtime)
	scripts/lock-python.sh

.PHONY: test
test: ## Lint + unit/integration tests (needs `docker compose up -d db`)
	. .venv/bin/activate && ruff check apps/ && ruff format --check apps/
	. .venv/bin/activate && cd apps/collector && python -m pytest -q
	. .venv/bin/activate && cd apps/api && DB_PORT=55432 DB_PASSWORD=weather-local-only DB_SSLMODE=disable python -m pytest -q
	cd apps/frontend && npm test

# --- Local Kubernetes (kind, provisioned by Terraform) --------------------------------
.PHONY: local-up
local-up: ## Create kind cluster + platform (Traefik, CNPG, metrics-server, Postgres)
	$(TERRAFORM) -chdir=$(LOCAL_ENV) init -input=false
	$(TERRAFORM) -chdir=$(LOCAL_ENV) apply -input=false -auto-approve

.PHONY: local-images
local-images: ## Build images and load them into kind
	for c in api collector frontend; do \
	  docker build -t weather/$$c:$(TAG) apps/$$c && kind load docker-image weather/$$c:$(TAG) --name $(CLUSTER); \
	done

.PHONY: local-deploy
local-deploy: local-images ## Offline fallback: Helm-deploy local images (normally Argo CD deploys)
	helm --kube-context $(KCTX) upgrade --install weather $(CHART) -n weather \
	  -f $(CHART)/ci/local-values.yaml --set image.tag=$(TAG) --wait --timeout 5m
	@echo "App: http://localhost:8088"

.PHONY: local-verify
local-verify: ## Prove NetworkPolicies are enforced
	$(KUBECTL) config use-context $(KCTX) >/dev/null && scripts/verify-netpol.sh

.PHONY: local-down
local-down: ## Destroy the local cluster
	$(TERRAFORM) -chdir=$(LOCAL_ENV) destroy -input=false -auto-approve

# --- Static checks (same as CI) --------------------------------------------------------
.PHONY: test-alerts
test-alerts: ## Unit-test Prometheus alert rules with promtool
	$(PROMTOOL) check rules deploy/charts/weather/rules/weather.rules.yaml
	$(PROMTOOL) test rules deploy/charts/weather/rules/tests/*.yaml
	scripts/check-runbooks.sh

.PHONY: lint-infra
lint-infra: ## terraform fmt/validate + helm lint + checkov
	$(TERRAFORM) fmt -check -recursive infra
	for d in infra/bootstrap infra/global infra/environments/*/; do \
	  $(TERRAFORM) -chdir=$$d init -backend=false -input=false >/dev/null && $(TERRAFORM) -chdir=$$d validate || exit 1; \
	done
	for env in local dev prod; do helm lint $(CHART) -f deploy/environments/$$env/values.yaml --set image.tag=lint --strict || exit 1; done
	.venv-tools/bin/checkov -d infra --framework terraform --quiet --compact --skip-download --skip-path '\.terraform'
