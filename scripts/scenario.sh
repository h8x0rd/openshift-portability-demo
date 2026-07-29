#!/usr/bin/env bash
set -euo pipefail
ns="${GITOPS_NAMESPACE:-openshift-gitops}"
placement="portability-demo-targets"
scenario="${1:-}"
usage(){ cat <<EOF
Usage: $0 <primary|secondary|active-active|auto-failover|remove>

 primary       Run only in eu-west-3
 secondary     Move to eu-west-2
 active-active Run in both regions
 auto-failover Select one available cluster from both regions
 remove        Select no clusters and prune the generated applications
EOF
}
[[ -n "$scenario" ]] || { usage; exit 1; }

case "$scenario" in
 primary) file=hub/placement-scenarios/eu-west-3.yaml ;;
 secondary) file=hub/placement-scenarios/eu-west-2.yaml ;;
 active-active) file=hub/placement-scenarios/both-regions.yaml ;;
 auto-failover) file=hub/placement-scenarios/auto-failover.yaml ;;
 remove) file=hub/placement-scenarios/none.yaml ;;
 *) usage; exit 1 ;;
esac

oc apply -f "$file"
oc annotate placement "$placement" -n "$ns" demo.portability/last-scenario="$scenario" --overwrite >/dev/null
printf 'Applied scenario: %s\n\n' "$scenario"

for _ in {1..30}; do
  selected=$(oc get placementdecision -n "$ns" \
    -l cluster.open-cluster-management.io/placement="$placement" \
    -o jsonpath='{range .items[*].status.decisions[*]}{.clusterName}{" "}{end}' 2>/dev/null || true)
  [[ -n "$selected" || "$scenario" == remove ]] && break
  sleep 2
done
./scripts/status.sh
