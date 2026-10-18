#!/usr/bin/env bash
# Run every quirk (or the ones named: run-all.sh 03 05) and write results.txt, one line per quirk:
# <quirk>: <verdict> | <summary>. Each quirk's full output goes to logs/<quirk>.log.
set -uo pipefail
QUIRKS="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$QUIRKS/logs"
: >"$QUIRKS/results.txt"
for dir in "$QUIRKS"/[0-9][0-9]-*/; do
  name=$(basename "$dir")
  if (( $# )); then
    match=0; for n in "$@"; do [[ $name == "$n"* ]] && match=1; done
    (( match )) || continue
  fi
  echo "== $name"
  bash "$dir/run.sh" >"$QUIRKS/logs/$name.log" 2>&1
  verdict=$(tail -1 "$QUIRKS/logs/$name.log")
  summary=$(grep '^summary: ' "$QUIRKS/logs/$name.log" | tail -1 | sed 's/^summary: //')
  case $verdict in REPRODUCED|"NOT REPRODUCED"|SKIPPED*) ;; *) verdict="ERROR (see logs/$name.log)";; esac
  echo "$name: $verdict${summary:+ | $summary}" | tee -a "$QUIRKS/results.txt"
done
