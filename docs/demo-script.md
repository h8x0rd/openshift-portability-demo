# Presenter script

## Opening

“Application portability should be a change in fleet intent, not a rewrite of
the workload. This repository contains one Helm chart. ACM decides which AWS
region should run it, and OpenShift GitOps reconciles that decision.”

## Scene 1: Confirm readiness

```bash
oc get managedclusters -L region -L cloud -L vendor
```

Confirm:

- `cluster1-sno`: `AVAILABLE=True`, `region=eu-west-3`
- `cluster2-sno`: `AVAILABLE=True`, `region=eu-west-2`

## Scene 2: Start in eu-west-3

Show that `hub/30-application-placement.yaml` selects `eu-west-3`.

Open the application route on `cluster1-sno` and point out the rendered cluster
name and AWS region.

## Scene 3: Relocate to eu-west-2

```bash
cp hub/placement-scenarios/eu-west-2.yaml hub/30-application-placement.yaml
git add hub/30-application-placement.yaml
git commit -m "Move portability demo to eu-west-2"
git push
```

Narrate:

1. ACM recalculates the PlacementDecision.
2. `cluster1-sno` leaves the decision.
3. `cluster2-sno` enters the decision.
4. ApplicationSet removes the old generated Application.
5. ApplicationSet creates the new generated Application.
6. Argo CD deploys the same Helm chart to `cluster2-sno`.

## Scene 4: Expand across both regions

```bash
cp hub/placement-scenarios/both-regions.yaml hub/30-application-placement.yaml
git add hub/30-application-placement.yaml
git commit -m "Expand portability demo across both AWS regions"
git push
```

Show both generated Applications healthy.

## Scene 5: One application update

Change `application.version` or `application.message` in `values.yaml`, commit,
and push. Show both selected clusters reconcile the same change.

## Closing

“ACM owns fleet selection. Git owns application and placement intent. Argo CD
owns reconciliation. The application can move between AWS regions or run in
both without maintaining separate workload definitions.”
