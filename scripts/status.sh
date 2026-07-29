#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"; require_hub
printf '
OpenShift Application Portability Demo
======================================
'
printf 'Scenario: %s

' "$(scenario_name)"
printf 'Root Argo CD application
'
if oc get applications.argoproj.io portability-demo-hub -n "$GITOPS_NAMESPACE" >/dev/null 2>&1; then
  oc get applications.argoproj.io portability-demo-hub -n "$GITOPS_NAMESPACE" \
    -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --no-headers | sed 's/^/  /'
  conditions=$(oc get applications.argoproj.io portability-demo-hub -n "$GITOPS_NAMESPACE" -o json | jq -r '.status.conditions[]? | "[\(.type)] \(.message)"')
  [[ -z "$conditions" ]] || printf '%s
' "$conditions" | sed 's/^/    /'
else
  printf '  not created
'
fi
printf '
'
printf 'Managed clusters
'
while read -r c; do [[ -z "$c" ]] && continue; role=$(oc get managedcluster "$c" -o jsonpath='{.metadata.labels.demo\.portability/role}'); avail=$(oc get managedcluster "$c" -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}'); taints=$(oc get managedcluster "$c" -o jsonpath='{range .spec.taints[*]}{.key}{","}{end}'); printf '  %-28s role=%-9s available=%-7s %s
' "$c" "$role" "$avail" "${taints:+taints=$taints}"; done < <(clusters_in_set)
printf '
Placement decision
'; selected_clusters | sed 's/^/  /' || true
printf '
Generated Argo CD applications
'; oc get applications.argoproj.io -n "$GITOPS_NAMESPACE" -l "$APP_LABEL" -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --no-headers 2>/dev/null | sed 's/^/  /' || true
