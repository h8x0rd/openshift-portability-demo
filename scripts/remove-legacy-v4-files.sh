#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

legacy=(
  charts/portability-demo/values-cluster1-sno.yaml
  charts/portability-demo/values-cluster2-sno.yaml
  hub/placement-scenarios/both-regions.yaml
  hub/placement-scenarios/eu-west-2.yaml
  hub/placement-scenarios/eu-west-3.yaml
  scripts/move.sh
)

found=()
for path in "${legacy[@]}"; do
  [[ -e "$path" ]] && found+=("$path")
done

if ((${#found[@]} == 0)); then
  echo "No known v4 legacy files were found."
  exit 0
fi

printf 'The following v4 files are obsolete in v5:\n'
printf '  %s\n' "${found[@]}"
printf '\nRemoving them from the working tree...\n'
rm -f -- "${found[@]}"
echo "✓ Legacy v4 files removed"
echo "Review with: git status --short"
echo "Commit the deletions together with the v5 upgrade."
