#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

ns="${GITOPS_NAMESPACE:-openshift-gitops}"
placement="portability-demo-targets"
managed_placement="hub/30-application-placement.yaml"
scenario="${1:-}"

usage() {
  cat <<'USAGE'
Usage: ./scripts/scenario.sh <primary|secondary|active-active|auto-failover|remove> [--no-push]

 primary       Run only in eu-west-3
 secondary     Move to eu-west-2
 active-active Run in both regions
 auto-failover Select one available cluster from both regions
 remove        Select no clusters and prune the generated applications

By default, the script updates the Git-managed Placement, commits the change,
and pushes the current branch. Use --no-push to create the local commit only.
USAGE
}

[[ -n "$scenario" ]] || { usage; exit 1; }
shift || true
push=true
if [[ "${1:-}" == "--no-push" ]]; then
  push=false
  shift
fi
[[ $# -eq 0 ]] || { usage; exit 1; }

case "$scenario" in
  primary)       file="hub/placement-scenarios/eu-west-3.yaml" ;;
  secondary)     file="hub/placement-scenarios/eu-west-2.yaml" ;;
  active-active) file="hub/placement-scenarios/both-regions.yaml" ;;
  auto-failover) file="hub/placement-scenarios/auto-failover.yaml" ;;
  remove)        file="hub/placement-scenarios/none.yaml" ;;
  *) usage; exit 1 ;;
esac

for command in git oc; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $command" >&2
    exit 1
  }
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "ERROR: run this script from a Git clone of the demo repository." >&2
  exit 1
}

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: the Git working tree contains uncommitted changes." >&2
  echo "Commit or stash them before changing the demo scenario." >&2
  git status --short >&2
  exit 1
fi

cp "$file" "$managed_placement"
git add "$managed_placement"

if git diff --cached --quiet; then
  echo "Scenario '$scenario' is already declared in Git."
else
  git commit -m "Set portability demo scenario: $scenario"
fi

if [[ "$push" == true ]]; then
  branch="$(git branch --show-current)"
  [[ -n "$branch" ]] || {
    echo "ERROR: detached HEAD; cannot push a scenario safely." >&2
    exit 1
  }
  git push origin "$branch"
  echo "Pushed scenario '$scenario' on branch '$branch'."
else
  echo "Created the local scenario commit. Push it before expecting GitOps reconciliation."
fi

if ! oc whoami >/dev/null 2>&1; then
  echo "WARNING: not logged in to the hub; skipping live reconciliation status."
  exit 0
fi

# A hard refresh reduces the wait when the repository webhook is not configured.
oc annotate applications.argoproj.io portability-demo-hub \
  -n "$ns" argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true

printf '\nWaiting for PlacementDecision reconciliation...\n'
for _ in {1..60}; do
  selected="$(oc get placementdecisions.cluster.open-cluster-management.io -n "$ns" \
    -l cluster.open-cluster-management.io/placement="$placement" \
    -o jsonpath='{range .items[*].status.decisions[*]}{.clusterName}{" "}{end}' 2>/dev/null || true)"

  if [[ "$scenario" == "remove" ]]; then
    [[ -z "$selected" ]] && break
  elif [[ -n "$selected" ]]; then
    case "$scenario" in
      primary)       [[ "$selected" == *"cluster1-sno"* ]] && break ;;
      secondary)     [[ "$selected" == *"cluster2-sno"* ]] && break ;;
      active-active) [[ "$selected" == *"cluster1-sno"* && "$selected" == *"cluster2-sno"* ]] && break ;;
      auto-failover) break ;;
    esac
  fi
  sleep 2
done

./scripts/status.sh
