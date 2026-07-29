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

- `<primary-cluster>`: `primary role`
- `<secondary-cluster>`: `secondary role`
- both belong to `demo-clusters`
- the hub is excluded from workload placement

## Scene 2: Show the current decision

```bash
oc get placementdecision -n openshift-gitops \
  -l cluster.open-cluster-management.io/placement=portability-demo-targets \
  -o yaml
```

Open the route on `<primary-cluster>`. The page should visibly report
`<primary-cluster>` and `primary role`.

## Scene 3: Move to secondary role

```bash
cp hub/placement-scenarios/secondary role.yaml \
  hub/30-application-placement.yaml

git add hub/30-application-placement.yaml
git commit -m "Move application to secondary role"
git push
```

Narrate the chain:

1. ACM recalculates the PlacementDecision.
2. ApplicationSet removes the old generated Application.
3. Argo CD prunes the workload from `<primary-cluster>`.
4. ApplicationSet creates a destination for `<secondary-cluster>`.
5. Argo CD deploys the same chart to `<secondary-cluster>`.

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
