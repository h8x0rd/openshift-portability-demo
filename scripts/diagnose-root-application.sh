#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
require_hub
need jq

app=portability-demo-hub
ns="$GITOPS_NAMESPACE"

printf '\nRoot Application diagnostics\n'
printf '============================\n\n'

if ! oc get applications.argoproj.io "$app" -n "$ns" >/dev/null 2>&1; then
  err "Application $app does not exist in $ns"
  printf 'Apply it with: oc apply -f bootstrap/portability-demo-hub.yaml\n' >&2
  exit 1
fi

json="$(oc get applications.argoproj.io "$app" -n "$ns" -o json)"
repo="$(jq -r '.spec.source.repoURL // ""' <<<"$json")"
revision="$(jq -r '.spec.source.targetRevision // ""' <<<"$json")"
path="$(jq -r '.spec.source.path // ""' <<<"$json")"
sync="$(jq -r '.status.sync.status // "Unknown"' <<<"$json")"
health="$(jq -r '.status.health.status // "Unknown"' <<<"$json")"
revision_seen="$(jq -r '.status.sync.revision // ""' <<<"$json")"

printf 'Application: %s/%s\n' "$ns" "$app"
printf 'Repository:  %s\n' "$repo"
printf 'Revision:    %s\n' "$revision"
printf 'Path:        %s\n' "$path"
printf 'Sync:        %s\n' "$sync"
printf 'Health:      %s\n' "$health"
printf 'Resolved SHA:%s\n\n' "${revision_seen:+ $revision_seen}"

printf 'Argo CD conditions\n'
if ! jq -e '.status.conditions | length > 0' <<<"$json" >/dev/null; then
  printf '  none reported\n'
else
  jq -r '.status.conditions[] | "  [\(.type)] \(.message)"' <<<"$json"
fi

printf '\nSource validation\n'
if [[ -z "$repo" || "$repo" == GIT_REPOSITORY_URL ]]; then
  printf '  ✗ Repository URL is not configured\n'
elif git ls-remote "$repo" "$revision" >/dev/null 2>&1; then
  printf '  ✓ Git repository and revision are reachable from this workstation\n'
else
  printf '  ✗ Git repository or revision is not reachable from this workstation\n'
  printf '    This does not test Argo CD credentials, but usually indicates an incorrect URL, branch, or authentication requirement.\n'
fi

if [[ -f "$ROOT_DIR/$path/kustomization.yaml" ]]; then
  printf '  ✓ Local source path exists: %s\n' "$path"
else
  printf '  ✗ Local source path is missing: %s\n' "$path"
fi

printf '\nExpected hub resources\n'
for object in \
  placement.cluster.open-cluster-management.io/portability-demo-registered-clusters \
  gitopscluster.apps.open-cluster-management.io/portability-demo-gitops \
  placement.cluster.open-cluster-management.io/portability-demo-targets \
  applicationset.argoproj.io/portability-demo; do
  if oc get "$object" -n "$ns" >/dev/null 2>&1; then
    printf '  ✓ %s\n' "$object"
  else
    printf '  ✗ %s\n' "$object"
  fi
done

printf '\nUseful controller logs\n'
printf '  oc logs -n %s deployment/openshift-gitops-repo-server --tail=200\n' "$ns"
printf '  oc logs -n %s statefulset/openshift-gitops-application-controller --tail=200\n' "$ns"
printf '\nThe most important output is the Argo CD condition above. Typical causes are an unreachable/private repository, an incorrect target revision, a missing source path, or repository credentials not configured in Argo CD.\n'
