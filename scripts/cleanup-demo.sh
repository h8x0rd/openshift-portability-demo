#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

ns="${GITOPS_NAMESPACE:-openshift-gitops}"
cluster1_context="${CLUSTER1_CONTEXT:-cluster1-sno}"
cluster2_context="${CLUSTER2_CONTEXT:-cluster2-sno}"
full=false
skip_git=false

usage() {
  cat <<'USAGE'
Usage: ./scripts/cleanup-demo.sh [--full] [--skip-git]

Default cleanup:
  1. Commits and pushes the 'remove' Placement scenario.
  2. Waits for generated Argo CD Applications to disappear.
  3. Deletes the root Argo CD Application and any remaining hub demo objects.
  4. Deletes the portability-demo namespace on managed clusters when matching
     kubeconfig contexts are available.
  5. Keeps ManagedClusterSet membership and binding for the next test.

Options:
  --full      Also remove demo-clusters binding, cluster-set membership labels,
              and the ManagedClusterSet. Use only when re-testing admin bootstrap.
  --skip-git  Do not commit/push the remove scenario. Use only when the repository
              has already been changed to the remove scenario.

Context overrides:
  CLUSTER1_CONTEXT=<context> CLUSTER2_CONTEXT=<context> ./scripts/cleanup-demo.sh
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) full=true ;;
    --skip-git) skip_git=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
  shift
done

command -v oc >/dev/null 2>&1 || { echo "ERROR: oc is required." >&2; exit 1; }
oc whoami >/dev/null 2>&1 || { echo "ERROR: log in to the ACM hub first." >&2; exit 1; }

if [[ "$skip_git" == false ]]; then
  ./scripts/scenario.sh remove
else
  echo "Skipping Git update; expecting the remove scenario to already be declared."
fi

echo "Waiting for generated workload Applications to be removed..."
for _ in {1..90}; do
  count="$(oc get applications.argoproj.io -n "$ns" \
    -l demo.portability/application=portability-demo \
    --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$count" == "0" ]] && break
  sleep 2
done

remaining="$(oc get applications.argoproj.io -n "$ns" \
  -l demo.portability/application=portability-demo \
  --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$remaining" != "0" ]]; then
  echo "WARNING: generated Applications still exist; deleting them explicitly."
  oc delete applications.argoproj.io -n "$ns" \
    -l demo.portability/application=portability-demo \
    --ignore-not-found --wait=true
fi

# Remove hub reconciliation first, then clear any resources left by an older iteration.
oc delete applications.argoproj.io portability-demo-hub -n "$ns" \
  --ignore-not-found --wait=true

oc delete applicationsets.argoproj.io portability-demo -n "$ns" --ignore-not-found
oc delete gitopsclusters.apps.open-cluster-management.io portability-demo-gitops \
  -n "$ns" --ignore-not-found
oc delete placements.cluster.open-cluster-management.io \
  portability-demo-targets portability-demo-registered-clusters \
  -n "$ns" --ignore-not-found

# PlacementDecision names are generated, so delete them by placement labels.
for p in portability-demo-targets portability-demo-registered-clusters; do
  oc delete placementdecisions.cluster.open-cluster-management.io -n "$ns" \
    -l cluster.open-cluster-management.io/placement="$p" \
    --ignore-not-found >/dev/null 2>&1 || true
done

cleanup_context() {
  local context="$1"
  if oc config get-contexts -o name | grep -Fxq "$context"; then
    echo "Deleting namespace portability-demo through context: $context"
    oc --context "$context" delete namespace portability-demo \
      --ignore-not-found --wait=true
  else
    echo "WARNING: kubeconfig context '$context' was not found."
    echo "         Delete namespace portability-demo manually on that managed cluster."
  fi
}

cleanup_context "$cluster1_context"
cleanup_context "$cluster2_context"

if [[ "$full" == true ]]; then
  echo "Removing one-time cluster-set prerequisites..."
  oc delete managedclustersetbindings.cluster.open-cluster-management.io demo-clusters \
    -n "$ns" --ignore-not-found

  for cluster in cluster1-sno cluster2-sno; do
    oc label managedclusters.cluster.open-cluster-management.io "$cluster" \
      cluster.open-cluster-management.io/clusterset- >/dev/null 2>&1 || true
  done

  oc delete managedclustersets.cluster.open-cluster-management.io demo-clusters \
    --ignore-not-found
fi

cat <<EOF

Cleanup complete.

Before the next test:
  git status
  ./scripts/bootstrap-demo.sh --check-only
  oc apply -f bootstrap/portability-demo-hub.yaml
  watch -n 2 './scripts/status.sh'

The repository currently declares the 'remove' scenario. After the hub bootstrap
is healthy, deploy the baseline with:
  ./scripts/scenario.sh primary

EOF
