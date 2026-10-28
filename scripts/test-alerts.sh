#!/usr/bin/env bash
# Unit-test every Prometheus rule file in the repo with promtool (CI + `make test-alerts`).
set -euo pipefail
cd "$(dirname "$0")/.."
PROMTOOL=${PROMTOOL:-promtool}

# App rules (shipped in the Helm chart).
$PROMTOOL check rules deploy/charts/weather/rules/weather.rules.yaml
$PROMTOOL test rules deploy/charts/weather/rules/tests/*.yaml

# DB rules are a Terraform template: render ${db_instances} the same way Terraform does.
L=infra/environments/local/rules
trap 'rm -f $L/tests/database.rules.rendered.yaml' EXIT
sed 's/\${db_instances}/2/' $L/database.rules.yaml > $L/tests/database.rules.rendered.yaml
$PROMTOOL check rules $L/tests/database.rules.rendered.yaml
$PROMTOOL test rules $L/tests/database.rules.test.yaml

scripts/check-runbooks.sh
