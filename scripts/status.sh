#!/usr/bin/env bash
set -euo pipefail
ns="${GITOPS_NAMESPACE:-openshift-gitops}"

echo '== Managed clusters =='
oc get managedclusters -L cluster.open-cluster-management.io/clusterset -L region -L cloud -L vendor

echo; echo '== Placement decisions =='
oc get placementdecisions -n "$ns" \
  -o custom-columns=NAME:.metadata.name,CLUSTERS:.status.decisions[*].clusterName

echo; echo '== GitOpsCluster =='
oc get gitopscluster portability-demo-gitops -n "$ns" \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase 2>/dev/null || true
oc get gitopscluster portability-demo-gitops -n "$ns" \
  -o jsonpath='{range .status.conditions[*]}{.type}{"="}{.status}{"  "}{.message}{"\n"}{end}' 2>/dev/null || true

echo; echo '== Argo CD applications =='
oc get applications.argoproj.io -n "$ns" \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,DESTINATION:.spec.destination.name
