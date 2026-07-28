#!/usr/bin/env bash
set -euo pipefail

oc patch placement portability-demo-targets -n openshift-gitops --type=merge -p '{
  "spec": {
    "predicates": [{
      "requiredClusterSelector": {
        "labelSelector": {
          "matchExpressions": [
            {"key":"region","operator":"In","values":["disabled"]}
          ]
        }
      }
    }]
  }
}'

echo "All application destinations cleared."
