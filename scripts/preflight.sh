#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

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

if oc get applications.argoproj.io portability-demo-hub -n "$GITOPS_NAMESPACE" >/dev/null 2>&1; then
  check_ok "Root Argo CD Application exists"
else
  check_warn "Root Application does not exist yet; apply bootstrap/portability-demo-hub.yaml"
fi

if ((failures > 0)); then
  printf '\n%sPreflight failed with %d error(s).%s\n' "$red" "$failures" "$reset" >&2
  exit 1
fi

printf '\n'
ok "Preflight passed"
