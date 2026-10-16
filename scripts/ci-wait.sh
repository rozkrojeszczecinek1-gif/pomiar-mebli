#!/usr/bin/env bash
# Czeka na zakończenie CI dla bieżącego commita; przy błędzie drukuje logi.
set -uo pipefail
GH="${GH:-gh}"
command -v "$GH" >/dev/null 2>&1 || GH="/c/Program Files/GitHub CLI/gh.exe"
sha=$(git rev-parse HEAD)
id=""
for _ in $(seq 1 12); do
  id=$("$GH" run list --commit "$sha" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
  [ -n "$id" ] && break
  sleep 5
done
[ -z "$id" ] && { echo "Brak przebiegu CI dla $sha"; exit 2; }
if ! "$GH" run watch "$id" --exit-status >/tmp/ci-watch.txt 2>&1; then
  tail -5 /tmp/ci-watch.txt
  "$GH" run view "$id" --log-failed | tail -150
  exit 1
fi
echo "CI OK: run $id"
