#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
require_hub
need jq

cluster="${1:-}"
if [[ -z "$cluster" ]]; then
  cluster="$(oc get managedclusters -l demo.portability/simulated-failure=true \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | head -1)"
fi
[[ -n "$cluster" ]] || die "No cluster marked with a simulated failure was found."

simulated="$(oc get managedcluster "$cluster" \
  -o jsonpath='{.metadata.labels.demo\.portability/simulated-failure}')"
[[ "$simulated" == true ]] || \
  die "$cluster is not marked as a simulated failure; refusing to remove its taint."

idx="$(oc get managedcluster "$cluster" -o json | jq -r '
  .spec.taints // []
  | to_entries[]
  | select(.value.key=="demo.portability/simulated-unreachable")
  | .key' | head -1)"
[[ -n "$idx" ]] || die "$cluster has no demo simulated-unreachable taint."

patch="[{\"op\":\"remove\",\"path\":\"/spec/taints/$idx\"}]"
oc patch managedcluster "$cluster" --type=json -p="$patch" >/dev/null
oc label managedcluster "$cluster" demo.portability/simulated-failure- >/dev/null
ok "$cluster is eligible for Placement again"
info "Steady prioritization may keep the workload on its current cluster. Use scenario.sh primary for controlled failback."
