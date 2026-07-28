#!/usr/bin/env bash
set -euo pipefail

region="${1:?Usage: $0 <eu-west-3|eu-west-2>}"
case "$region" in
  eu-west-3|eu-west-2) ;;
  *) echo "Unsupported demo region: $region" >&2; exit 1 ;;
esac

oc patch placement portability-demo-targets -n openshift-gitops --type=merge -p "{
  \"spec\": {
    \"predicates\": [{
      \"requiredClusterSelector\": {
        \"labelSelector\": {
          \"matchExpressions\": [
            {\"key\":\"vendor\",\"operator\":\"In\",\"values\":[\"OpenShift\"]},
            {\"key\":\"cloud\",\"operator\":\"In\",\"values\":[\"Amazon\"]},
            {\"key\":\"region\",\"operator\":\"In\",\"values\":[\"$region\"]}
          ]
        }
      }
    }]
  }
}"

echo "Application placement moved to AWS region: $region"
oc get placementdecision -n openshift-gitops \
  -l cluster.open-cluster-management.io/placement=portability-demo-targets
