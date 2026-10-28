#!/usr/bin/env bash
# Compile requirements*.in -> hash-pinned requirements*.txt inside python:3.12-slim
# (the runtime image), so environment markers match production, not the laptop.
# Streams files via stdin/stdout: works even where Docker can't bind-mount the repo.
set -euo pipefail
cd "$(dirname "$0")/../apps"
compile() {
  local dir=$1 name=$2
  (cd "$dir" && tar -cf - "$name.in" $( [ -f requirements.txt ] && echo requirements.txt ) |
    docker run --rm -i python:3.12-slim sh -c \
      "mkdir /w && cd /w && tar -xf - && pip install -q pip-tools >/dev/null 2>&1 &&
       pip-compile -q --generate-hashes --strip-extras --no-header --allow-unsafe -o - $name.in" \
    > "$name.txt.new" && mv "$name.txt.new" "$name.txt")
  echo "locked $dir/$name.txt"
}
for c in api collector; do
  compile "$c" requirements
  compile "$c" requirements-dev   # constrained by requirements.txt (-c)
done
