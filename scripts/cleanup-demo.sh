#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"; require_hub
full=false; [[ "${1:-}" == --full ]] && full=true
info "Switching Git to remove scenario"; "$ROOT_DIR/scripts/scenario.sh" remove || warn "Scenario switch failed; continuing with explicit cleanup"
oc delete applications.argoproj.io -n "$GITOPS_NAMESPACE" -l "$APP_LABEL" --ignore-not-found
oc delete applications.argoproj.io portability-demo-hub -n "$GITOPS_NAMESPACE" --ignore-not-found
oc delete applicationsets.argoproj.io "$APPSET_NAME" -n "$GITOPS_NAMESPACE" --ignore-not-found
oc delete gitopsclusters.apps.open-cluster-management.io portability-demo -n "$GITOPS_NAMESPACE" --ignore-not-found
oc delete placements.cluster.open-cluster-management.io portability-demo-targets portability-demo-registered-clusters -n "$GITOPS_NAMESPACE" --ignore-not-found
while read -r c; do
  [[ -z "$c" ]] && continue
  simulated=$(oc get managedcluster "$c" -o jsonpath='{.metadata.labels.demo\.portability/simulated-failure}')
  [[ "$simulated" == true ]] || continue
  idx=$(oc get managedcluster "$c" -o json | jq -r '.spec.taints // [] | to_entries[] | select(.value.key=="demo.portability/simulated-unreachable") | .key' | head -1)
  [[ -n "$idx" ]] && oc patch managedcluster "$c" --type=json -p="[{\"op\":\"remove\",\"path\":\"/spec/taints/$idx\"}]" || true
  oc label managedcluster "$c" demo.portability/simulated-failure- || true
done < <(clusters_in_set)
if $full; then while read -r c; do oc label managedcluster "$c" cluster.open-cluster-management.io/clusterset- demo.portability/role- || true; done < <(clusters_in_set); oc delete managedclustersetbinding "$CLUSTERSET_NAME" -n "$GITOPS_NAMESPACE" --ignore-not-found; oc delete managedclusterset "$CLUSTERSET_NAME" --ignore-not-found; fi
ok "Hub cleanup complete. Workload namespaces on unreachable managed clusters may require direct cleanup after recovery."
