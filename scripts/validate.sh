#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

errors=0
warnings=0

pass() { printf 'PASS: %s\n' "$1"; }
warn() { printf 'WARN: %s\n' "$1" >&2; warnings=$((warnings + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; errors=$((errors + 1)); }

require_file() {
  if [[ -f "$1" ]]; then
    pass "Required file exists: $1"
  else
    fail "Required file is missing: $1"
  fi
}

normalise_git_url() {
  local url="$1"
  case "$url" in
    git@github.com:*) printf 'https://github.com/%s\n' "${url#git@github.com:}" ;;
    git@gitlab.com:*) printf 'https://gitlab.com/%s\n' "${url#git@gitlab.com:}" ;;
    ssh://git@github.com/*) printf 'https://github.com/%s\n' "${url#ssh://git@github.com/}" ;;
    ssh://git@gitlab.com/*) printf 'https://gitlab.com/%s\n' "${url#ssh://git@gitlab.com/}" ;;
    *) printf '%s\n' "$url" ;;
  esac
}

required_files=(
  bootstrap/portability-demo-hub.yaml
  hub/20-gitops-cluster.yaml
  hub/30-application-placement.yaml
  hub/40-application-set.yaml
  hub/kustomization.yaml
  charts/portability-demo/Chart.yaml
  charts/portability-demo/values.yaml
)
for path in "${required_files[@]}"; do
  require_file "$path"
done

if ((errors)); then
  printf '\nValidation stopped because required files are missing.\n' >&2
  exit 1
fi

python3 - <<'PY'
from pathlib import Path
import sys
try:
    import yaml
except ImportError:
    print("FAIL: Python module 'yaml' is unavailable; install PyYAML", file=sys.stderr)
    raise SystemExit(1)
for path in sorted(Path('.').rglob('*.yaml')):
    if 'templates' in path.parts:
        continue
    with path.open() as stream:
        list(yaml.safe_load_all(stream))
print('PASS: YAML parsed successfully')
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
  fail 'Legacy v4 files remain'
  printf '  %s\n' "${legacy_found[@]}" >&2
  printf '  Run ./scripts/remove-legacy-v4-files.sh and commit the deletions.\n' >&2
else
  pass 'No legacy v4 files remain'
fi

if matches="$(grep -RInE 'cluster1-sno|cluster2-sno|eu-west-[0-9]|h8x0rd' \
    README.md CHANGELOG.md bootstrap charts docs hub prerequisites scripts \
    --exclude=validate.sh --exclude=remove-legacy-v4-files.sh 2>/dev/null || true)" && [[ -n "$matches" ]]; then
  fail 'Environment-specific names remain'
  printf '%s\n' "$matches" >&2
else
  pass 'No prohibited environment-specific names found'
fi

placeholder_pattern='GIT_REPOSITORY_URL|GIT_TARGET_REVISION|REPOSITORY_URL_PLACEHOLDER|TARGET_REVISION_PLACEHOLDER'
if matches="$(grep -RInE "$placeholder_pattern" bootstrap charts hub 2>/dev/null || true)" && [[ -n "$matches" ]]; then
  fail 'Repository configuration placeholders remain'
  printf '%s\n' "$matches" >&2
  printf '\n  Run ./scripts/configure-repository.sh before continuing.\n' >&2
else
  pass 'No repository configuration placeholders remain'
fi

readarray -t config_values < <(python3 - <<'PY'
import yaml

def read(path):
    with open(path) as stream:
        return yaml.safe_load(stream)
root = read('bootstrap/portability-demo-hub.yaml')
appset = read('hub/40-application-set.yaml')
print(root['spec']['source']['repoURL'])
print(root['spec']['source']['targetRevision'])
print(appset['spec']['template']['spec']['source']['repoURL'])
print(appset['spec']['template']['spec']['source']['targetRevision'])
print(appset['spec']['generators'][0]['clusterDecisionResource']['labelSelector']['matchLabels']['cluster.open-cluster-management.io/placement'])
print(read('hub/20-gitops-cluster.yaml')['spec']['placementRef']['name'])
print(appset['spec']['template']['spec']['destination']['server'])
print(appset['spec']['template']['metadata']['name'])
PY
)

root_repo="${config_values[0]}"
root_revision="${config_values[1]}"
appset_repo="${config_values[2]}"
appset_revision="${config_values[3]}"
workload_placement="${config_values[4]}"
registration_placement="${config_values[5]}"
destination_server="${config_values[6]}"
application_name="${config_values[7]}"

if [[ "$root_repo" == "$appset_repo" ]]; then
  pass 'Root Application and ApplicationSet repository URLs match'
else
  fail "Repository URL mismatch: root='$root_repo', ApplicationSet='$appset_repo'"
fi

if [[ "$root_revision" == "$appset_revision" ]]; then
  pass 'Root Application and ApplicationSet revisions match'
else
  fail "Revision mismatch: root='$root_revision', ApplicationSet='$appset_revision'"
fi

[[ "$registration_placement" == 'portability-demo-registered-clusters' ]] \
  && pass 'GitOpsCluster references the registration Placement' \
  || fail "Unexpected GitOpsCluster placementRef: $registration_placement"

[[ "$workload_placement" == 'portability-demo-targets' ]] \
  && pass 'ApplicationSet references the workload Placement' \
  || fail "Unexpected ApplicationSet Placement selector: $workload_placement"

[[ "$destination_server" == '{{ .server }}' ]] \
  && pass 'ApplicationSet destination is generated from the selected cluster server' \
  || fail "Unexpected ApplicationSet destination server template: $destination_server"

[[ "$application_name" == 'portability-demo-{{ .name }}' ]] \
  && pass 'Generated Application name is cluster-derived' \
  || fail "Unexpected generated Application name template: $application_name"

if grep -Fqx '  - 20-gitops-cluster.yaml' hub/kustomization.yaml \
   && grep -Fqx '  - 30-application-placement.yaml' hub/kustomization.yaml \
   && grep -Fqx '  - 40-application-set.yaml' hub/kustomization.yaml; then
  pass 'Hub kustomization includes core GitOps resources'
else
  fail 'Hub kustomization does not include all core GitOps resources'
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  origin="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -n "$origin" ]]; then
    normalised_origin="$(normalise_git_url "$origin")"
    if [[ "$normalised_origin" == "$root_repo" ]]; then
      pass 'Configured repository matches the normalised Git origin'
    else
      warn "Configured repository differs from Git origin: origin='$origin', configured='$root_repo'"
    fi
  else
    warn 'Git remote origin is not configured'
  fi

  if git rev-parse --verify "${root_revision}^{commit}" >/dev/null 2>&1; then
    pass "Configured revision resolves locally: $root_revision"
  else
    warn "Configured revision does not resolve locally: $root_revision"
  fi

  configured_paths=(bootstrap/portability-demo-hub.yaml hub/40-application-set.yaml)
  if ! git diff --quiet -- "${configured_paths[@]}"; then
    warn 'Repository configuration files contain uncommitted changes'
  elif ! git diff --cached --quiet -- "${configured_paths[@]}"; then
    warn 'Repository configuration files are staged but not committed'
  else
    pass 'Repository configuration files are committed locally'
  fi
else
  warn 'Not running inside a Git work tree; Git consistency checks skipped'
fi

printf '\nValidation summary: %d error(s), %d warning(s)\n' "$errors" "$warnings"
if ((errors)); then
  exit 1
fi
printf 'Repository validation passed\n'
