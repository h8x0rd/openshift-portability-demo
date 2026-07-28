#!/usr/bin/env bash
set -euo pipefail

oc patch placement portability-demo-targets -n openshift-gitops --type=merge -p '{
  "spec": {
    "predicates": [{
      "requiredClusterSelector": {
        "labelSelector": {
          "matchExpressions": [
            {"key":"vendor","operator":"In","values":["OpenShift"]},
            {"key":"cloud","operator":"In","values":["Amazon"]},
            {"key":"region","operator":"In","values":["eu-west-3","eu-west-2"]}
          ]
        }
      }
    }]
  }
}'

echo "Application placement expanded to eu-west-3 and eu-west-2."
