#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<USAGE
Usage:
  $0 --primary <managedcluster> --secondary <managedcluster>
  $0 --check-only

When exactly two non-hub managed clusters exist, --primary and --secondary may be omitted.
USAGE
}

primary="${PRIMARY_CLUSTER:-}"
secondary="${SECONDARY_CLUSTER:-}"
check_only=false

while (($#)); do
  case "$1" in
    --primary) primary="${2:?Missing value for --primary}"; shift 2 ;;
    --secondary) secondary="${2:?Missing value for --secondary}"; shift 2 ;;
    --check-only) check_only=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "Unknown argument: $1" ;;
  esac
done

require_hub
need jq

if $check_only; then
  primary="$(cluster_by_role primary)"
  secondary="$(cluster_by_role secondary)"
  [[ -n "$primary" ]] || die "No managed cluster is labelled demo.portability/role=primary."
  [[ -n "$secondary" ]] || die "No managed cluster is labelled demo.portability/role=secondary."
else
  if [[ -z "$primary" || -z "$secondary" ]]; then
    mapfile -t available < <(
      oc get managedclusters -o json | jq -r \
        '.items[] | select(.metadata.name != "local-cluster") | .metadata.name'
    )
    [[ ${#available[@]} -eq 2 ]] || die \
      "Specify --primary and --secondary. Automatic selection requires exactly two non-hub managed clusters; found ${#available[@]}."
    primary="${available[0]}"
    secondary="${available[1]}"
    warn "Automatically selected primary=$primary and secondary=$secondary"
  fi

  [[ "$primary" != "$secondary" ]] || die "Primary and secondary must be different clusters."
  for cluster in "$primary" "$secondary"; do
    oc get managedcluster "$cluster" >/dev/null 2>&1 || die "ManagedCluster not found: $cluster"
  done

  oc apply -f "$ROOT_DIR/prerequisites/clusterset-and-binding.yaml"
  oc label managedcluster "$primary" \
    "cluster.open-cluster-management.io/clusterset=$CLUSTERSET_NAME" \
    'demo.portability/role=primary' --overwrite
  oc label managedcluster "$secondary" \
    "cluster.open-cluster-management.io/clusterset=$CLUSTERSET_NAME" \
    'demo.portability/role=secondary' --overwrite
fi

oc get managedclusterset "$CLUSTERSET_NAME" >/dev/null 2>&1 || die "ManagedClusterSet $CLUSTERSET_NAME is missing."
oc get managedclustersetbinding "$CLUSTERSET_NAME" -n "$GITOPS_NAMESPACE" >/dev/null 2>&1 || \
  die "ManagedClusterSetBinding $CLUSTERSET_NAME is missing from $GITOPS_NAMESPACE."
[[ "$(cluster_by_role primary)" == "$primary" ]] || die "$primary is not labelled as the primary role."
[[ "$(cluster_by_role secondary)" == "$secondary" ]] || die "$secondary is not labelled as the secondary role."

ok "Reusable administrator prerequisites are valid"
ok "Primary:   $primary"
ok "Secondary: $secondary"

if ! $check_only; then
  echo
  echo "Next steps:"
  echo "  1. ./scripts/configure-repository.sh"
  echo "  2. git add . && git commit -m 'Configure portability demo' && git push"
  echo "  3. oc apply -f bootstrap/portability-demo-hub.yaml"
  echo "  4. ./scripts/preflight.sh"
fi
