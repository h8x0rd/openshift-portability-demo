#!/usr/bin/env bash
set -o pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GITOPS_NAMESPACE="${GITOPS_NAMESPACE:-openshift-gitops}"
CLUSTERSET_NAME="${CLUSTERSET_NAME:-demo-clusters}"
PLACEMENT_NAME="${PLACEMENT_NAME:-portability-demo-targets}"
APPSET_NAME="${APPSET_NAME:-portability-demo}"
APP_LABEL="demo.portability/application=portability-demo"
FAILOVER_TAINT="demo.portability/simulated-unreachable"
red='[31m'; green='[32m'; yellow='[33m'; blue='[34m'; reset='[0m'
ok(){ printf "${green}✓${reset} %s
" "$*"; }
info(){ printf "${blue}→${reset} %s
" "$*"; }
warn(){ printf "${yellow}!${reset} %s
" "$*"; }
die(){ printf "${red}✗${reset} %s
" "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
require_hub(){ need oc; oc whoami >/dev/null 2>&1 || die "Log in to the ACM hub with oc first."; }
clusters_in_set(){ oc get managedclusters -l "cluster.open-cluster-management.io/clusterset=${CLUSTERSET_NAME}" -o jsonpath='{range .items[*]}{.metadata.name}{"
"}{end}'; }
cluster_by_role(){ oc get managedclusters -l "cluster.open-cluster-management.io/clusterset=${CLUSTERSET_NAME},demo.portability/role=$1" -o jsonpath='{range .items[*]}{.metadata.name}{"
"}{end}' | head -1; }
selected_clusters(){ oc get placementdecisions.cluster.open-cluster-management.io -n "$GITOPS_NAMESPACE" -l "cluster.open-cluster-management.io/placement=${PLACEMENT_NAME}" -o jsonpath='{range .items[*].status.decisions[*]}{.clusterName}{"
"}{end}' 2>/dev/null; }
scenario_name(){ grep -A4 'demo.portability/role' "$ROOT_DIR/hub/30-application-placement.yaml" 2>/dev/null | grep -q 'primary, secondary' && { grep -q 'numberOfClusters: 2' "$ROOT_DIR/hub/30-application-placement.yaml" && echo active-active || echo auto-failover; return; }; grep -A4 'demo.portability/role' "$ROOT_DIR/hub/30-application-placement.yaml" | grep -q primary && echo primary && return; grep -A4 'demo.portability/role' "$ROOT_DIR/hub/30-application-placement.yaml" | grep -q secondary && echo secondary && return; echo remove; }
