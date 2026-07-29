# OpenShift Application Portability Demo

A reusable, GitOps-driven demonstration of application mobility across two ACM-managed OpenShift clusters. ACM Placement chooses the destination, an Argo CD ApplicationSet translates that decision into an Application, and OpenShift GitOps reconciles the same Helm chart on the selected cluster.

## What it demonstrates

- Planned movement between primary and secondary clusters
- Active-active deployment to both clusters
- Availability-driven failover using ACM-compatible `NoSelect` taints
- Git as the source of truth for every scenario
- Automated pruning, recovery and clean reset

No cluster names, cloud providers, regions or Git repository URLs are embedded in the release. Cluster roles are expressed through labels:

```text
demo.portability/role=primary
demo.portability/role=secondary
```

## Prerequisites

- Red Hat Advanced Cluster Management hub with two imported managed clusters
- OpenShift GitOps and the ACM GitOps integration
- `oc`, `git`, `jq`, and `python3`
- Permission to create/bind a ManagedClusterSet and label ManagedClusters

## Clone and configure

```bash
git clone <your-fork-url>
cd openshift-portability-demo
./scripts/configure-repository.sh
```

The configuration script reads the `origin` URL and current branch automatically. Alternatively:

```bash
./scripts/configure-repository.sh <repository-url> <branch-or-tag>
```

Commit and push the generated repository settings:

```bash
git add .
git commit -m "Configure portability demo repository"
git push
```

## Assign reusable cluster roles

```bash
./scripts/bootstrap-demo.sh   --primary <first-managedcluster-name>   --secondary <second-managedcluster-name>
```

When exactly two non-hub managed clusters exist, the script can infer them:

```bash
./scripts/bootstrap-demo.sh
```

Validate the result:

```bash
./scripts/bootstrap-demo.sh   --primary <first-managedcluster-name>   --secondary <second-managedcluster-name>   --check-only
```

## Deploy the hub application

```bash
oc apply -f bootstrap/portability-demo-hub.yaml
./scripts/preflight.sh
./scripts/watch-demo.sh
```

## Scenarios

```bash
./scripts/scenario.sh primary
./scripts/scenario.sh secondary
./scripts/scenario.sh active-active
./scripts/scenario.sh auto-failover
./scripts/scenario.sh remove
```

Each scenario copies the appropriate Placement into the Git-managed manifest, commits it, pushes it and waits for reconciliation. Use `--no-push` to inspect the commit before pushing.

### Availability-driven single-cluster failover mode

Activate a single-cluster Placement that can select either role:

```bash
./scripts/scenario.sh auto-failover
```

This mode does not move the workload merely because a pod fails. ACM Placement evaluates managed-cluster eligibility. The failover test therefore applies the same `cluster.open-cluster-management.io/unreachable:NoSelect` taint used for an unreachable managed cluster.

Start the automated test without naming a cluster; the script discovers the currently selected destination:

```bash
./scripts/failover.sh
```

It verifies the scenario, taints the selected ManagedCluster, waits for the PlacementDecision to move, and prints the resulting Argo CD state. A specific selected cluster can be supplied as a guard:

```bash
./scripts/failover.sh <managedcluster-name>
```

Observe the control loop:

```bash
./scripts/watch-demo.sh
```

Recover the failed cluster by discovery:

```bash
./scripts/recover.sh
```

or explicitly:

```bash
./scripts/recover.sh <managedcluster-name>
```

The `Steady` prioritizer may keep the workload on the surviving cluster after recovery. This avoids oscillation. Perform a controlled failback with:

```bash
./scripts/scenario.sh primary
```

During a genuine network partition, hub-based Argo CD can deploy to the surviving cluster but cannot guarantee immediate pruning from the unreachable cluster. Stateful applications additionally require data replication, fencing and split-brain protection. Client traffic also needs a global ingress or DNS failover layer.

## Status and preflight

```bash
./scripts/status.sh
./scripts/watch-demo.sh 3
./scripts/preflight.sh
```

The status view discovers cluster roles, availability, taints, Placement decisions and generated Argo CD Applications dynamically.

## Cleanup and retest

Standard reset keeps the ManagedClusterSet and role assignments:

```bash
./scripts/cleanup-demo.sh
```

Full reset also removes cluster-set membership and role labels:

```bash
./scripts/cleanup-demo.sh --full
```

Retest:

```bash
./scripts/bootstrap-demo.sh --primary <cluster-a> --secondary <cluster-b>
./scripts/configure-repository.sh
git add . && git commit -m "Configure demo" && git push
oc apply -f bootstrap/portability-demo-hub.yaml
./scripts/scenario.sh primary
./scripts/watch-demo.sh
```

## Repository layout

```text
bootstrap/       Root Argo CD Application
charts/          Portable demonstration workload
hub/             ACM Placement, GitOpsCluster and ApplicationSet
prerequisites/   ManagedClusterSet and binding
scripts/         Setup, scenarios, failover, recovery and cleanup
docs/            Presenter and troubleshooting guidance
```

## Security and production boundaries

The sample workload runs non-root, drops Linux capabilities, uses RuntimeDefault seccomp, resource limits and health probes. The repository demonstrates control-plane portability, not a complete disaster-recovery platform. Production designs must address persistent data, secrets, identity, networking, DNS, traffic draining, fencing, RPO and RTO.
