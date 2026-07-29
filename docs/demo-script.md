# Presenter script

## Opening

“Application portability should be a change in fleet intent, not a rewrite of
the workload. This repository contains one Helm chart. ACM decides which AWS
region should run it, and OpenShift GitOps reconciles that decision.”

## Scene 1: Show fleet readiness

```bash
oc get managedclusters \
  -L region \
  -L cloud \
  -L vendor \
  -L cluster.open-cluster-management.io/clusterset
```

Highlight:

- `cluster1-sno`: `eu-west-3`
- `cluster2-sno`: `eu-west-2`
- both belong to `demo-clusters`
- the hub is excluded from workload placement

## Scene 2: Show the current decision

```bash
oc get placementdecision -n openshift-gitops \
  -l cluster.open-cluster-management.io/placement=portability-demo-targets \
  -o yaml
```

Open the route on `cluster1-sno`. The page should visibly report
`cluster1-sno` and `eu-west-3`.

## Scene 3: Move to eu-west-2

```bash
cp hub/placement-scenarios/eu-west-2.yaml \
  hub/30-application-placement.yaml

git add hub/30-application-placement.yaml
git commit -m "Move application to eu-west-2"
git push
```

Narrate the chain:

1. ACM recalculates the PlacementDecision.
2. ApplicationSet removes the old generated Application.
3. Argo CD prunes the workload from `cluster1-sno`.
4. ApplicationSet creates a destination for `cluster2-sno`.
5. Argo CD deploys the same chart to `cluster2-sno`.

## Scene 4: Expand to both regions

```bash
cp hub/placement-scenarios/both-regions.yaml \
  hub/30-application-placement.yaml

git add hub/30-application-placement.yaml
git commit -m "Expand application across both AWS regions"
git push
```

Show two healthy generated Applications and both Routes.

## Scene 5: Demonstrate one application update

Change `application.version` or `application.message` in `values.yaml`, commit,
and push. Explain that the ConfigMap checksum causes a controlled rollout on
every selected destination.

## Closing

“ACM owns fleet selection. Git owns placement and application intent. Argo CD
owns reconciliation. The application can move or expand without maintaining
separate workload manifests.”
