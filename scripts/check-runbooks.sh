#!/usr/bin/env bash
# Every alert must link a runbook that exists. Fails CI on a dangling runbook_url or an
# alert without one - a broken link at 3am is worse than no link.
set -euo pipefail
cd "$(dirname "$0")/.."
files=(deploy/charts/weather/rules/weather.rules.yaml infra/environments/local/manifests/*.tftpl)
rc=0
alerts=$(grep -hc -- "- alert:" "${files[@]}" | paste -sd+ - | bc)
links=$(grep -hc "runbook_url:" "${files[@]}" | paste -sd+ - | bc)
[ "$alerts" -eq "$links" ] || { echo "FAIL: $alerts alerts but $links runbook_url annotations"; rc=1; }
for f in $(grep -hoE "docs/runbooks/[A-Za-z]+\.md" "${files[@]}" | sort -u); do
  [ -f "$f" ] || { echo "FAIL: missing $f"; rc=1; }
done
[ $rc -eq 0 ] && echo "runbooks OK: $alerts alerts, all linked and present"
exit $rc
