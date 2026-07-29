#!/usr/bin/env bash
set -euo pipefail

failed=0

check_file() {
  [[ -f "$1" ]] || { echo "ERROR: missing $1" >&2; failed=1; }
}

for file in \
  bootstrap/portability-demo-hub.yaml \
  prerequisites/clusterset-and-binding.yaml \
  hub/kustomization.yaml \
  hub/40-application-set.yaml \
  charts/portability-demo/Chart.yaml \
  charts/portability-demo/values.yaml \
  charts/portability-demo/templates/deployment.yaml; do
  check_file "$file"
done

if grep -Rqs 'YOUR_ORG' bootstrap hub charts; then
  echo "ERROR: repository placeholder YOUR_ORG is still present." >&2
  failed=1
fi

if command -v helm >/dev/null 2>&1; then
  helm lint charts/portability-demo
  helm template portability-demo charts/portability-demo \
    -f charts/portability-demo/values-cluster1-sno.yaml >/dev/null
else
  echo "WARN: helm is not installed; Helm lint/render checks were skipped."
fi

if command -v oc >/dev/null 2>&1; then
  oc kustomize hub >/dev/null
else
  echo "WARN: oc is not installed; Kustomize render check was skipped."
fi

if (( failed )); then
  exit 1
fi

echo "Repository structure validation passed."
