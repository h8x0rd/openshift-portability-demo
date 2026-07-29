#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
usage(){ echo "Usage: $0 --primary <managedcluster> --secondary <managedcluster> [--check-only]"; }
primary="${PRIMARY_CLUSTER:-}"; secondary="${SECONDARY_CLUSTER:-}"; check=false
while (($#)); do case "$1" in --primary) primary="$2"; shift 2;; --secondary) secondary="$2"; shift 2;; --check-only) check=true; shift;; *) usage; exit 1;; esac; done
require_hub
if [[ -z "$primary" || -z "$secondary" ]]; then
  mapfile -t available < <(oc get managedclusters -o jsonpath='{range .items[?(@.metadata.name!="local-cluster")]}{.metadata.name}{"
"}{end}')
  [[ ${#available[@]} -eq 2 ]] || die "Specify --primary and --secondary. Automatic selection works only when exactly two non-hub managed clusters exist."
  primary="${available[0]}"; secondary="${available[1]}"
  warn "Automatically selected primary=$primary and secondary=$secondary"
fi
[[ "$primary" != "$secondary" ]] || die "Primary and secondary must be different clusters."
for c in "$primary" "$secondary"; do oc get managedcluster "$c" >/dev/null || die "ManagedCluster not found: $c"; done
if $check; then
  [[ "$(cluster_by_role primary)" == "$primary" ]] || die "$primary is not labelled primary"
  [[ "$(cluster_by_role secondary)" == "$secondary" ]] || die "$secondary is not labelled secondary"
  oc get managedclusterset "$CLUSTERSET_NAME" >/dev/null || die "ManagedClusterSet missing"
  oc get managedclustersetbinding "$CLUSTERSET_NAME" -n "$GITOPS_NAMESPACE" >/dev/null || die "ManagedClusterSetBinding missing"
  ok "Reusable demo prerequisites are valid"; exit 0
fi
oc apply -f "$ROOT_DIR/prerequisites/clusterset-and-binding.yaml"
for pair in "$primary primary" "$secondary secondary"; do read -r c role <<<"$pair"; oc label managedcluster "$c" cluster.open-cluster-management.io/clusterset="$CLUSTERSET_NAME" demo.portability/role="$role" --overwrite; ok "$c assigned role $role"; done
ok "Bootstrap complete: primary=$primary secondary=$secondary"
echo "Next: ./scripts/configure-repository.sh && git commit && git push && oc apply -f bootstrap/portability-demo-hub.yaml"
