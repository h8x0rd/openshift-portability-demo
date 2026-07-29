#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"; require_hub
need git; need jq
[[ -z "$(grep -RIl 'GIT_REPOSITORY_URL\|GIT_TARGET_REVISION' "$ROOT_DIR/hub" "$ROOT_DIR/bootstrap" "$ROOT_DIR/charts" || true)" ]] || die "Repository placeholders remain. Run configure-repository.sh."
mapfile -t clusters < <(clusters_in_set); ((${#clusters[@]}==2)) || die "Expected exactly two demo clusters in $CLUSTERSET_NAME; found ${#clusters[@]}"
[[ -n "$(cluster_by_role primary)" ]] || die "No primary role assigned"; [[ -n "$(cluster_by_role secondary)" ]] || die "No secondary role assigned"
oc get managedclustersetbinding "$CLUSTERSET_NAME" -n "$GITOPS_NAMESPACE" >/dev/null || die "ManagedClusterSetBinding missing"
oc get configmap acm-placement -n "$GITOPS_NAMESPACE" >/dev/null || warn "acm-placement ConfigMap not found yet"
ok "Environment ready: primary=$(cluster_by_role primary), secondary=$(cluster_by_role secondary)"
