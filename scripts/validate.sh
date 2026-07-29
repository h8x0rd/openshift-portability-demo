#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path
import yaml
for path in sorted(Path('.').rglob('*.yaml')):
    if 'templates' in path.parts:
        continue
    with path.open() as stream:
        list(yaml.safe_load_all(stream))
print('YAML parsed successfully')
PY

legacy=(
  charts/portability-demo/values-cluster1-sno.yaml
  charts/portability-demo/values-cluster2-sno.yaml
  hub/placement-scenarios/both-regions.yaml
  hub/placement-scenarios/eu-west-2.yaml
  hub/placement-scenarios/eu-west-3.yaml
  scripts/move.sh
)
legacy_found=()
for path in "${legacy[@]}"; do
  [[ -e "$path" ]] && legacy_found+=("$path")
done
if ((${#legacy_found[@]})); then
  printf 'Legacy v4 files remain:\n' >&2
  printf '  %s\n' "${legacy_found[@]}" >&2
  printf 'Run ./scripts/remove-legacy-v4-files.sh and commit the deletions.\n' >&2
  exit 1
fi

if grep -RInE 'cluster1-sno|cluster2-sno|eu-west-[0-9]|h8x0rd' \
  README.md CHANGELOG.md bootstrap charts docs hub prerequisites scripts \
  --exclude=validate.sh --exclude=remove-legacy-v4-files.sh; then
  echo 'Environment-specific names remain' >&2
  exit 1
fi

if grep -RIl 'GIT_REPOSITORY_URL\|GIT_TARGET_REVISION' bootstrap charts hub >/dev/null 2>&1; then
  echo 'Repository placeholders remain; run ./scripts/configure-repository.sh' >&2
  exit 1
fi

repo_urls="$(grep -RhE '^\s*(repoURL|gitRepository):' bootstrap charts hub | sed -E 's/^\s*[^:]+:\s*//' | sort -u)"
if [[ "$(wc -l <<<"$repo_urls" | tr -d ' ')" -ne 1 ]]; then
  echo 'Configured repository URLs are inconsistent:' >&2
  printf '%s\n' "$repo_urls" >&2
  exit 1
fi

echo 'Repository validation passed'
