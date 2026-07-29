#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${GITOPS_NAMESPACE:-openshift-gitops}"
CLUSTERSET="${CLUSTERSET_NAME:-demo-clusters}"
CLUSTERS=("${CLUSTER1_NAME:-cluster1-sno}" "${CLUSTER2_NAME:-cluster2-sno}")
DRY_RUN=false
[[ "${1:-}" == "--check-only" ]] && DRY_RUN=true

ok(){ printf '\033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m!\033[0m %s\n' "$*"; }
fail(){ printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }
has_api(){ oc api-resources --api-group="$1" -o name 2>/dev/null | sed "s/\..*//" | grep -qx "$2"; }

need oc
oc whoami >/dev/null 2>&1 || fail "Not logged in to the hub cluster"
ok "Connected to hub as $(oc whoami)"

for pair in \
  'cluster.open-cluster-management.io managedclusters' \
  'cluster.open-cluster-management.io managedclustersets' \
  'cluster.open-cluster-management.io managedclustersetbindings' \
  'cluster.open-cluster-management.io placements' \
  'cluster.open-cluster-management.io placementdecisions' \
  'apps.open-cluster-management.io gitopsclusters' \
  'argoproj.io applications' \
  'argoproj.io applicationsets'; do
  read -r group resource <<<"$pair"
  has_api "$group" "$resource" || fail "Required API missing: $resource.$group"
done
ok "ACM and OpenShift GitOps APIs are available"

oc get namespace "$NAMESPACE" >/dev/null 2>&1 || fail "Namespace $NAMESPACE does not exist"
oc get deployment openshift-gitops-server -n "$NAMESPACE" >/dev/null 2>&1 || \
  warn "Default Argo CD server deployment was not found; verify your Argo CD instance name"
ok "GitOps namespace is present"

for cluster in "${CLUSTERS[@]}"; do
  oc get managedcluster "$cluster" >/dev/null 2>&1 || fail "ManagedCluster not found: $cluster"
  joined=$(oc get managedcluster "$cluster" -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterJoined")].status}')
  available=$(oc get managedcluster "$cluster" -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}')
  [[ "$joined" == True ]] || fail "$cluster is not joined"
  [[ "$available" == True ]] || warn "$cluster is currently not available"
  ok "$cluster is imported and joined"
done

if [[ "$DRY_RUN" == true ]]; then
  oc get managedclusterset "$CLUSTERSET" >/dev/null 2>&1 || fail "ManagedClusterSet $CLUSTERSET is missing"
  oc get managedclustersetbinding "$CLUSTERSET" -n "$NAMESPACE" >/dev/null 2>&1 || fail "Binding $NAMESPACE/$CLUSTERSET is missing"
  for cluster in "${CLUSTERS[@]}"; do
    current=$(oc get managedcluster "$cluster" -o jsonpath='{.metadata.labels.cluster\.open-cluster-management\.io/clusterset}')
    [[ "$current" == "$CLUSTERSET" ]] || fail "$cluster is not assigned to $CLUSTERSET"
  done
  ok "Cluster-set preparation is complete"
  exit 0
fi

oc auth can-i create managedclustersets.cluster.open-cluster-management.io >/dev/null || fail "Cluster-admin-equivalent rights are required"
oc auth can-i create managedclustersets/bind.cluster.open-cluster-management.io >/dev/null || \
  fail "User cannot bind ManagedClusterSets; run this script as cluster-admin"
ok "Cluster-set administrative permissions confirmed"

oc apply -f prerequisites/clusterset-and-binding.yaml
for cluster in "${CLUSTERS[@]}"; do
  oc label managedcluster "$cluster" \
    cluster.open-cluster-management.io/clusterset="$CLUSTERSET" --overwrite
  ok "Assigned $cluster to $CLUSTERSET"
done

oc get managedclusterset "$CLUSTERSET" >/dev/null
oc get managedclustersetbinding "$CLUSTERSET" -n "$NAMESPACE" >/dev/null
ok "One-time cluster-set preparation completed"

echo
echo "Next: oc apply -f bootstrap/portability-demo-hub.yaml"
