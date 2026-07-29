#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

mode="auto"
case "${1:-}" in
  "") ;;
  --platform) mode="platform" ;;
  --deployment) mode="deployment" ;;
  -h|--help)
    cat <<'USAGE'
Usage: ./scripts/preflight.sh [--platform|--deployment]

  --platform    Validate the repository, ACM, GitOps, permissions and cluster roles
                before applying the root Argo CD Application.
  --deployment  Require the root Application to be Synced and all hub resources to exist.
  no option     Automatically performs platform checks and, when the root Application
                exists, also performs deployment checks.
USAGE
    exit 0
    ;;
  *) die "Unknown option: ${1}" ;;
esac

require_hub
need git
need jq

failures=0
check_ok() { ok "$1"; }
check_fail() { printf '%s✗%s %s\n' "$red" "$reset" "$1" >&2; failures=$((failures + 1)); }
check_warn() { warn "$1"; }

printf '\nOpenShift Application Portability Demo preflight\n'
printf '================================================\n\n'

if grep -RIl 'GIT_REPOSITORY_URL\|GIT_TARGET_REVISION' \
  "$ROOT_DIR/hub" "$ROOT_DIR/bootstrap" "$ROOT_DIR/charts" >/dev/null 2>&1; then
  check_fail "Repository placeholders remain. Run ./scripts/configure-repository.sh, commit, and push."
else
  check_ok "Repository URL and revision are configured"
fi

configured_repo="$(oc create --dry-run=client -f "$ROOT_DIR/bootstrap/portability-demo-hub.yaml" -o json 2>/dev/null | jq -r '.spec.source.repoURL // empty' || true)"
if [[ "$configured_repo" == git@* || "$configured_repo" == ssh://* ]]; then
  matching_secret=false
  while IFS= read -r encoded_url; do
    [[ -n "$encoded_url" ]] || continue
    secret_url="$(printf '%s' "$encoded_url" | base64 -d 2>/dev/null || true)"
    if [[ "$secret_url" == "$configured_repo" ]]; then
      matching_secret=true
      break
    fi
  done < <(oc get secrets -n "$GITOPS_NAMESPACE" -l argocd.argoproj.io/secret-type=repository -o json 2>/dev/null | jq -r '.items[].data.url // empty')
  if $matching_secret; then
    check_ok "Argo CD SSH repository credentials exist for $configured_repo"
  else
    check_fail "Repository uses SSH but no matching Argo CD repository Secret was found: $configured_repo"
    printf '%s\n' '    A local SSH agent cannot be used by the Argo CD repo-server.' >&2
    printf '%s\n' '    For a public GitHub/GitLab repository, rerun ./scripts/configure-repository.sh to use HTTPS.' >&2
    printf '%s\n' '    For a private SSH repository, configure its deploy key in OpenShift GitOps first.' >&2
  fi
elif [[ -n "$configured_repo" ]]; then
  check_ok "Argo CD repository source uses HTTP(S): $configured_repo"
fi

if oc get multiclusterhub -A >/dev/null 2>&1; then
  check_ok "ACM MultiClusterHub API is available"
else
  check_fail "ACM MultiClusterHub was not found"
fi

if oc api-resources --api-group=cluster.open-cluster-management.io | grep -q '^placements'; then
  check_ok "ACM Placement APIs are available"
else
  check_fail "ACM Placement API is unavailable"
fi

if oc api-resources --api-group=apps.open-cluster-management.io | grep -q '^gitopsclusters'; then
  check_ok "ACM GitOpsCluster API is available"
else
  check_fail "GitOpsCluster API is unavailable; verify ACM GitOps integration"
fi

if oc api-resources --api-group=argoproj.io | grep -q '^applicationsets'; then
  check_ok "Argo CD ApplicationSet API is available"
else
  check_fail "ApplicationSet API is unavailable; verify OpenShift GitOps"
fi

if oc get namespace "$GITOPS_NAMESPACE" >/dev/null 2>&1; then
  check_ok "Namespace $GITOPS_NAMESPACE exists"
else
  check_fail "Namespace $GITOPS_NAMESPACE does not exist"
fi

if oc get managedclusterset "$CLUSTERSET_NAME" >/dev/null 2>&1; then
  check_ok "ManagedClusterSet $CLUSTERSET_NAME exists"
else
  check_fail "ManagedClusterSet $CLUSTERSET_NAME is missing; run ./scripts/bootstrap-demo.sh"
fi

if oc get managedclustersetbinding "$CLUSTERSET_NAME" -n "$GITOPS_NAMESPACE" >/dev/null 2>&1; then
  check_ok "ManagedClusterSetBinding exists in $GITOPS_NAMESPACE"
else
  check_fail "ManagedClusterSetBinding is missing; run bootstrap as a hub cluster administrator"
fi

mapfile -t clusters < <(clusters_in_set)
if ((${#clusters[@]} == 2)); then
  check_ok "Exactly two managed clusters belong to $CLUSTERSET_NAME"
else
  check_fail "Expected exactly two demo clusters in $CLUSTERSET_NAME; found ${#clusters[@]}"
fi

primary="$(cluster_by_role primary)"
secondary="$(cluster_by_role secondary)"
[[ -n "$primary" ]] && check_ok "Primary role: $primary" || check_fail "No primary role is assigned"
[[ -n "$secondary" ]] && check_ok "Secondary role: $secondary" || check_fail "No secondary role is assigned"

for cluster in "${clusters[@]}"; do
  [[ -n "$cluster" ]] || continue
  joined="$(oc get managedcluster "$cluster" -o json | jq -r '.status.conditions[]? | select(.type=="ManagedClusterJoined") | .status' | tail -1)"
  available="$(oc get managedcluster "$cluster" -o json | jq -r '.status.conditions[]? | select(.type=="ManagedClusterConditionAvailable") | .status' | tail -1)"
  if [[ "$joined" == True ]]; then
    check_ok "$cluster is joined"
  else
    check_fail "$cluster is not joined (ManagedClusterJoined=$joined)"
  fi
  if [[ "$available" == True ]]; then
    check_ok "$cluster is available"
  else
    check_warn "$cluster is not currently available (ManagedClusterConditionAvailable=$available)"
  fi
done

root_exists=false
if oc get applications.argoproj.io portability-demo-hub -n "$GITOPS_NAMESPACE" >/dev/null 2>&1; then
  root_exists=true
fi

if [[ "$mode" == "platform" ]]; then
  if $root_exists; then
    check_warn "Root Application already exists; --platform intentionally does not validate its reconciliation"
  else
    check_ok "Root Application has not been applied yet"
  fi
elif $root_exists; then
  check_ok "Root Argo CD Application exists"

  root_json="$(oc get applications.argoproj.io portability-demo-hub -n "$GITOPS_NAMESPACE" -o json)"
  root_sync="$(jq -r '.status.sync.status // "Unknown"' <<<"$root_json")"
  root_health="$(jq -r '.status.health.status // "Unknown"' <<<"$root_json")"

  if [[ "$root_sync" == "Synced" ]]; then
    check_ok "Root Application is Synced"
  else
    check_fail "Root Application is not Synced (sync=$root_sync, health=$root_health)"
    while IFS=$'\t' read -r type message; do
      [[ -n "$message" ]] && printf '    Argo CD %s: %s\n' "$type" "$message" >&2
    done < <(jq -r '.status.conditions[]? | [.type, .message] | @tsv' <<<"$root_json")
    printf '    Run ./scripts/diagnose-root-application.sh for focused diagnostics.\n' >&2
  fi

  declare -a hub_objects=(
    "placement.cluster.open-cluster-management.io/portability-demo-registered-clusters"
    "gitopscluster.apps.open-cluster-management.io/portability-demo-gitops"
    "placement.cluster.open-cluster-management.io/portability-demo-targets"
    "applicationset.argoproj.io/portability-demo"
  )
  for object in "${hub_objects[@]}"; do
    if oc get "$object" -n "$GITOPS_NAMESPACE" >/dev/null 2>&1; then
      check_ok "Hub resource exists: $object"
    else
      check_fail "Hub resource is missing: $object"
    fi
  done
else
  if [[ "$mode" == "deployment" ]]; then
    check_fail "Root Application does not exist; apply bootstrap/portability-demo-hub.yaml"
  else
    check_warn "Root Application does not exist yet; platform preflight is complete"
  fi
fi

if ((failures > 0)); then
  printf '\n%sPreflight failed with %d error(s).%s\n' "$red" "$failures" "$reset" >&2
  exit 1
fi

printf '\n'
ok "Preflight passed"
