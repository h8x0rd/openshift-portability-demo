# OpenShift Day-2 Operations & Application Mobility Demo

A reusable demonstration of fleet-aware application operations with **Red Hat Advanced Cluster Management (ACM)** and **Red Hat OpenShift GitOps**. A single Helm workload can be deployed, relocated, expanded, reconciled and availability-failed-over across two OpenShift SNO clusters by changing placement intent on the hub.

## What the demo proves

- **Portable deployment:** one chart and one Git revision across multiple clusters.
- **Planned mobility:** move a stateless application between AWS regions.
- **Active-active expansion:** deploy simultaneously to both clusters.
- **Availability-driven failover:** select one healthy destination from the eligible fleet.
- **Day-2 rollout:** Git changes trigger rolling updates.
- **Drift correction:** Argo CD self-heal restores declared state.
- **Clean decommissioning:** remove placement and prune generated applications.

> This is a stateless mobility demonstration. Placement and GitOps do not replicate persistent application data. See **Stateful DR boundary** below.

## Lab topology

| Cluster | Role | Region |
|---|---|---|
| `local-cluster` | ACM hub and OpenShift GitOps | Hub |
| `cluster1-sno` | Primary demo destination | `eu-west-3` |
| `cluster2-sno` | Secondary demo destination | `eu-west-2` |

## Control flow

```text
Git commit ──> OpenShift GitOps on hub
                    │
                    ├── GitOpsCluster registers eligible managed clusters
                    │
Placement intent ──> PlacementDecision
                    │
                    └── ApplicationSet generates one Argo CD Application
                        for each selected managed cluster
                                      │
                                      └── Helm workload + Route
```

## Repository layout

```text
bootstrap/                     Root Argo CD Application
prerequisites/                 One-time cluster-admin resources
hub/                           GitOpsCluster, Placements and ApplicationSet
hub/placement-scenarios/       Primary, secondary, active-active, failover, none
charts/portability-demo/       OpenShift-safe stateless Helm workload
scripts/bootstrap-demo.sh      Admin prerequisite validation/preparation
scripts/scenario.sh            Day-2 scenario controller
scripts/status.sh              End-to-end status view
docs/day2-runbook.md           Operator runbook
docs/presenter-script.md       Customer-demo narrative
```

# Administrator prerequisites

These are platform-level actions and should be completed once by a hub cluster administrator.

## 1. ACM hub and managed clusters

ACM must be installed and available, and both SNO clusters must already be imported. Verify:

```bash
oc get multiclusterhub -A
oc get managedclusters -L region -L cloud -L vendor
```

Both managed clusters must report `Joined=True` and `Available=True` before the initial demo.

## 2. OpenShift GitOps Operator and Argo CD instance

Install the Red Hat OpenShift GitOps Operator on the ACM hub. This repository expects the default Argo CD instance in `openshift-gitops`.

```bash
oc get csv -A | grep -i openshift-gitops
oc get deployments -n openshift-gitops
```

## 3. ACM GitOps integration APIs

The integration is ready when these APIs exist:

```bash
oc api-resources --api-group=apps.open-cluster-management.io | grep gitopsclusters
oc api-resources --api-group=cluster.open-cluster-management.io | grep -E 'placements|placementdecisions|managedclustersets'
oc api-resources --api-group=argoproj.io | grep -E 'applicationsets|applications'
```

Required resources:

- `GitOpsCluster`
- `Placement` and `PlacementDecision`
- `ManagedClusterSet` and `ManagedClusterSetBinding`
- Argo CD `Application` and `ApplicationSet`

The `GitOpsCluster` controller registers Placement-selected managed clusters with the Argo CD instance. The ApplicationSet cluster-decision generator then consumes the workload PlacementDecision.

## 4. One-time cluster-set preparation with cluster-admin

A `ManagedClusterSetBinding` projects a cluster-scoped set into the namespace containing the Placements. Creating it requires the protected `managedclustersets/bind` permission, which the application controller intentionally does not receive.

Run the bootstrap helper as cluster-admin:

```bash
./scripts/bootstrap-demo.sh
```

It performs all of the following:

1. Confirms login to the hub.
2. Verifies ACM, GitOps and integration APIs.
3. Verifies the two managed clusters are imported and joined.
4. Checks permission to create and bind a ManagedClusterSet.
5. Applies `prerequisites/clusterset-and-binding.yaml`.
6. Assigns both managed clusters to `demo-clusters`.
7. Verifies the binding exists in `openshift-gitops`.

To validate without changing anything:

```bash
./scripts/bootstrap-demo.sh --check-only
```

Manual equivalent:

```bash
oc apply -f prerequisites/clusterset-and-binding.yaml
oc label managedcluster cluster1-sno cluster.open-cluster-management.io/clusterset=demo-clusters --overwrite
oc label managedcluster cluster2-sno cluster.open-cluster-management.io/clusterset=demo-clusters --overwrite
oc get managedclustersetbinding demo-clusters -n openshift-gitops
```

# Demo-owner bootstrap

## 1. Configure and push the repository

```bash
./scripts/configure-repository.sh https://github.com/h8x0rd/openshift-portability-demo.git
./scripts/validate.sh
git add .
git commit -m 'Add Day-2 application mobility demo'
git push
```

## 2. Create the root Application

```bash
oc apply -f bootstrap/portability-demo-hub.yaml
```

Check the full chain:

```bash
./scripts/status.sh
```

Initially, `portability-demo-targets` selects `cluster1-sno`, and Argo CD should show:

```text
portability-demo-hub
portability-demo-cluster1-sno
```

Always use `applications.argoproj.io`; the short name `application` can resolve to a different Kubernetes API.

# Day-2 scenarios

## Planned move to the secondary cluster

```bash
./scripts/scenario.sh secondary
```

## Return to the primary cluster

```bash
./scripts/scenario.sh primary
```

## Expand to both clusters

```bash
./scripts/scenario.sh active-active
```

## Availability-driven single-cluster failover mode

```bash
./scripts/scenario.sh auto-failover
```

This sets `numberOfClusters: 1` across both eligible regions. The workload Placement has no unavailability tolerations, so unavailable/unreachable clusters are ineligible. The separate registration Placement does tolerate temporary unavailability so both destinations remain registered with Argo CD.

The scheduler selects an eligible cluster; this scenario does not promise a permanent primary preference. Use explicit `primary` and `secondary` scenarios for deterministic planned movement.

## Remove the workload everywhere

```bash
./scripts/scenario.sh remove
```

## Monitor reconciliation

```bash
watch -n 2 './scripts/status.sh'
```

See `docs/day2-runbook.md` and `docs/presenter-script.md` for the complete workshop sequence.

# Other integration considerations

Apart from ACM, the OpenShift GitOps Operator and cluster-set preparation, confirm:

- **Network reachability:** the hub’s Argo CD controller must be able to reach managed-cluster API endpoints in the selected push model.
- **Repository access:** configure repository credentials if the Git repository is private.
- **Image access:** managed clusters must be able to pull the workload image; mirror it for disconnected environments.
- **Argo CD project/RBAC:** this lab uses the `default` project. Production environments should use a dedicated AppProject with constrained repositories, destinations and resource kinds.
- **ManagedServiceAccount:** use the ACM-supported token management model appropriate to your product version and push/pull design; validate the required add-on if your GitOpsCluster configuration depends on it.
- **Application DNS/traffic:** relocation creates cluster-local Routes. A stable global hostname and automated traffic steering require an external DNS/GSLB layer and health checks.
- **Secrets:** do not keep application secrets in plain Git. Use an approved secret-management pattern such as External Secrets, Vault or sealed/encrypted GitOps secrets.
- **Observability:** use ACM observability and application metrics/logs to measure rollout and recovery time. This repository provides status commands, not a production SLO stack.

# Workload security and reliability

The chart uses a pinned unprivileged NGINX runtime on port `8080`, OpenShift-compatible restricted security settings, all Linux capabilities dropped, no service-account token, health probes, resource requests/limits, rolling updates and a ConfigMap checksum that triggers rollout when page content changes.

# Stateful DR boundary

The automatic failover scenario redeploys a **stateless** application. It does not move a database or persistent volume. True stateful disaster recovery needs storage replication, consistency controls, fencing, recovery orchestration and rehearsed operational procedures. In the Red Hat stack this commonly involves ODF regional or metro DR, VolSync where applicable, `DRPolicy` and `DRPlacementControl`.

# Validation and troubleshooting

```bash
./scripts/validate.sh
./scripts/bootstrap-demo.sh --check-only
./scripts/status.sh
```

Common checks:

```bash
oc get managedclustersetbindings -n openshift-gitops
oc get placementdecisions -n openshift-gitops
oc get gitopscluster portability-demo-gitops -n openshift-gitops -o yaml
oc get secrets -n openshift-gitops -l argocd.argoproj.io/secret-type=cluster
oc describe applicationset portability-demo -n openshift-gitops
oc get applications.argoproj.io -n openshift-gitops
```

See `docs/troubleshooting.md` for detailed fault isolation.
