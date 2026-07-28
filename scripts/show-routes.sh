#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 <managed-cluster-name> [managed-cluster-name ...]" >&2
  exit 1
fi

for cluster in "$@"; do
  secret="$(oc -n openshift-gitops get secret \
    -l argocd.argoproj.io/secret-type=cluster \
    -o jsonpath="{range .items[?(@.metadata.labels.name=='$cluster')]}{.metadata.name}{'\n'}{end}" 2>/dev/null || true)"
  echo "$cluster: inspect its portability-demo route from the managed cluster console"
done
