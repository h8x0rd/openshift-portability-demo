#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
require_hub
need jq

[[ "$(scenario_name)" == auto-failover ]] || \
  die "Activate auto-failover first: ./scripts/scenario.sh auto-failover"

current="${1:-$(selected_clusters | head -1)}"
[[ -n "$current" ]] || die "No selected cluster found."
oc get managedcluster "$current" >/dev/null 2>&1 || die "ManagedCluster not found: $current"

actual="$(selected_clusters | head -1)"
[[ "$current" == "$actual" ]] || die "$current is not the currently selected cluster ($actual)."

info "Simulating unreachability for $current"
existing="$(oc get managedcluster "$current" -o json | jq -r '.spec.taints[]?.key')"
if grep -qx 'cluster.open-cluster-management.io/unreachable' <<<"$existing"; then
  die "$current already has an unreachable taint; refusing to claim a potentially genuine outage."
fi

oc annotate managedcluster "$current" demo.portability/simulated-failure=true --overwrite >/dev/null
count="$(oc get managedcluster "$current" -o json | jq '.spec.taints // [] | length')"
if (( count == 0 )); then
  patch='[{"op":"add","path":"/spec/taints","value":[{"key":"cluster.open-cluster-management.io/unreachable","effect":"NoSelect"}]}]'
else
  patch='[{"op":"add","path":"/spec/taints/-","value":{"key":"cluster.open-cluster-management.io/unreachable","effect":"NoSelect"}}]'
fi
oc patch managedcluster "$current" --type=json -p="$patch" >/dev/null
ok "Applied simulated ACM unreachable taint to $current"

for i in {1..90}; do
  new="$(selected_clusters | head -1)"
  if [[ -n "$new" && "$new" != "$current" ]]; then
    ok "Placement failed over from $current to $new in $((i * 2)) seconds"
    "$ROOT_DIR/scripts/status.sh"
    exit 0
  fi
  sleep 2
done

die "Placement did not move within 180 seconds. Check Placement tolerations and cluster eligibility."
