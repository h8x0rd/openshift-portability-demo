# Day-2 Operations and Application Mobility Runbook

All commands run against the ACM hub. Scenario commands update Git, commit, and push the Placement intent; they do not patch the live Placement. The generated Argo CD Applications deploy to managed clusters through the cluster credentials registered by `GitOpsCluster`.

## Scenario 1 — Baseline on the primary region

```bash
./scripts/scenario.sh primary
```

Expected decision: `cluster1-sno`. Open its Route and point out the cluster and region identity rendered by the same Helm chart.

## Scenario 2 — Planned relocation

```bash
./scripts/scenario.sh secondary
```

ACM updates the PlacementDecision. ApplicationSet creates the application for `cluster2-sno`; Argo CD deploys it and prunes the former generated Application after the selection changes.

This demonstrates application mobility, not storage migration. The demo workload is stateless.

## Scenario 3 — Active-active expansion

```bash
./scripts/scenario.sh active-active
```

Both clusters are selected. One generated Argo CD Application exists per cluster. This demonstrates fleet-wide rollout from one Git revision.

## Scenario 4 — Availability-driven failover

```bash
./scripts/scenario.sh auto-failover
```

The Placement selects one available matching cluster. Because the workload Placement does not tolerate the ACM `unavailable` or `unreachable` taints, an unhealthy selected cluster becomes ineligible and the scheduler can select the surviving cluster.

Keep both clusters registered with Argo CD: the separate registration Placement deliberately tolerates temporary unavailability. That means the destination credential remains known while workload selection reacts to health.

To demonstrate safely, do not destroy a cluster. Temporarily mark the selected ManagedCluster unavailable only in a disposable lab, or interrupt its connectivity, then watch:

```bash
watch -n 2 './scripts/status.sh'
```

Recovery is control-plane driven and is not instantaneous. Detection, Placement reconciliation, ApplicationSet reconciliation, image pulling and Route readiness all contribute to recovery time.

## Scenario 5 — Remove all placements

```bash
./scripts/scenario.sh remove
```

The selector intentionally matches no clusters. ApplicationSet removes generated Applications and automated prune removes the stateless workload.

## Rollout demonstration

Change `application.version` or `application.message` in `charts/portability-demo/values.yaml`, commit, and push. The ConfigMap checksum changes the pod template, producing a rolling deployment with `maxUnavailable: 0`.

## Drift correction

Delete or edit a managed resource from a managed cluster. Argo CD self-heal restores the Git-declared state. Use only disposable resources belonging to this demo.

## Stateful DR boundary

This ApplicationSet demo does not replicate persistent data. Production stateful failover requires an application-aware DR design, commonly ODF regional/metro DR with `DRPolicy`, `DRPlacementControl`, storage replication and tested fencing/recovery procedures. Do not present Placement-only relocation as stateful disaster recovery.


## Clean reset before a new demonstration

```bash
./scripts/cleanup-demo.sh
```

Use `--full` to also remove the ManagedClusterSet and binding before repeating the
administrator bootstrap. When the managed-cluster kubeconfig context names differ,
set `CLUSTER1_CONTEXT` and `CLUSTER2_CONTEXT`.

After cleanup:

```bash
./scripts/bootstrap-demo.sh
oc apply -f bootstrap/portability-demo-hub.yaml
./scripts/scenario.sh primary
```
