#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"; cd "$ROOT_DIR"
scenario="${1:-}"; [[ -n "$scenario" ]] || die "Usage: $0 <primary|secondary|active-active|auto-failover|remove> [--no-push]"
push=true; [[ "${2:-}" == --no-push ]] && push=false
case "$scenario" in primary|secondary|active-active|auto-failover|remove) file="hub/placement-scenarios/$scenario.yaml";; *) die "Unknown scenario: $scenario";; esac
need git; git diff --quiet && git diff --cached --quiet || die "Commit or stash existing changes first."
cp "$file" hub/30-application-placement.yaml; git add hub/30-application-placement.yaml
if ! git diff --cached --quiet; then git commit -m "Set portability demo scenario: $scenario"; fi
if $push; then branch=$(git branch --show-current); [[ -n "$branch" ]] || die "Detached HEAD"; git push origin "$branch"; fi
if oc whoami >/dev/null 2>&1; then
 oc annotate applications.argoproj.io portability-demo-hub -n "$GITOPS_NAMESPACE" argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
 expected=""; case "$scenario" in primary|secondary) expected=$(cluster_by_role "$scenario");; esac
 for _ in {1..60}; do mapfile -t selected < <(selected_clusters); case "$scenario" in remove) ((${#selected[@]}==0)) && break;; active-active) ((${#selected[@]}>=2)) && break;; auto-failover) ((${#selected[@]}==1)) && break;; primary|secondary) [[ " ${selected[*]} " == *" $expected "* ]] && break;; esac; sleep 2; done
 "$ROOT_DIR/scripts/status.sh"
fi
