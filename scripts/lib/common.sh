#!/usr/bin/env bash
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GITOPS_NAMESPACE="${GITOPS_NAMESPACE:-openshift-gitops}"
CLUSTERSET_NAME="${CLUSTERSET_NAME:-demo-clusters}"
PLACEMENT_NAME="${PLACEMENT_NAME:-portability-demo-targets}"
APPSET_NAME="${APPSET_NAME:-portability-demo}"
APP_LABEL="demo.portability/application=portability-demo"

red=$'\033[31m'
green=$'\033[32m'
yellow=$'\033[33m'
blue=$'\033[34m'
reset=$'\033[0m'

ok()   { printf '%s✓%s %s\n' "$green" "$reset" "$*"; }
info() { printf '%s→%s %s\n' "$blue" "$reset" "$*"; }
warn() { printf '%s!%s %s\n' "$yellow" "$reset" "$*"; }
die()  { printf '%s✗%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_hub() {
  need oc
  oc whoami >/dev/null 2>&1 || die "Log in to the ACM hub with 'oc login' first."
}

clusters_in_set() {
  oc get managedclusters \
    -l "cluster.open-cluster-management.io/clusterset=${CLUSTERSET_NAME}" \
    -o json | jq -r '.items[].metadata.name'
}

cluster_by_role() {
  local role="$1"
  oc get managedclusters \
    -l "cluster.open-cluster-management.io/clusterset=${CLUSTERSET_NAME},demo.portability/role=${role}" \
    -o json | jq -r '.items[0].metadata.name // empty'
}

selected_clusters() {
  oc get placementdecisions.cluster.open-cluster-management.io \
    -n "$GITOPS_NAMESPACE" \
    -l "cluster.open-cluster-management.io/placement=${PLACEMENT_NAME}" \
    -o json 2>/dev/null | jq -r '.items[].status.decisions[]?.clusterName'
}

scenario_name() {
  local file="$ROOT_DIR/hub/30-application-placement.yaml"
  [[ -f "$file" ]] || { echo unknown; return; }

  if grep -q 'numberOfClusters: 0' "$file"; then
    echo remove
  elif grep -q 'numberOfClusters: 2' "$file"; then
    echo active-active
  elif grep -A8 'demo.portability/role' "$file" | grep -q 'primary, secondary'; then
    echo auto-failover
  elif grep -A8 'demo.portability/role' "$file" | grep -q 'primary'; then
    echo primary
  elif grep -A8 'demo.portability/role' "$file" | grep -q 'secondary'; then
    echo secondary
  else
    echo unknown
  fi
}
