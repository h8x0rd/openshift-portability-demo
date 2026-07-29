# OpenShift Application Portability Demo

A reusable, GitOps-driven demonstration of application mobility across two Red Hat Advanced Cluster Management (ACM)-managed OpenShift clusters.

ACM Placement decides where the application should run. An Argo CD ApplicationSet consumes the PlacementDecision and generates an Argo CD Application for each selected cluster. OpenShift GitOps then deploys the same Helm chart and Git revision to the selected destination.

The repository is deliberately environment-neutral. It contains no fixed managed-cluster names, cloud regions, provider assumptions, usernames, or personal Git repository URLs.

## What the demo proves

- **Portable deployment:** one application definition and one Git revision across multiple OpenShift clusters.
- **Planned mobility:** move the workload deliberately between primary and secondary roles.
- **Active-active deployment:** run the same workload on both clusters.
- **Availability-driven failover:** automatically select another eligible cluster when the current destination becomes unavailable.
- **GitOps reconciliation:** every scenario is committed to Git rather than patched directly on the hub.
- **Drift correction:** Argo CD restores declared state when live resources are changed.
- **Clean decommissioning:** remove generated Applications and workloads predictably.

> This is a stateless application-mobility demonstration. It does not replicate persistent data or provide application-level disaster recovery by itself.

## Logical topology

| Component | Purpose |
|---|---|
| ACM hub | Hosts ACM, OpenShift GitOps, Placement resources, GitOpsCluster and ApplicationSet |
| Primary-role managed cluster | Preferred destination for the baseline scenario |
| Secondary-role managed cluster | Alternate destination and failover target |
| Git repository | Source of truth for hub resources, Placement intent and Helm workload |

Cluster roles are represented by portable labels:

```text
demo.portability/role=primary
demo.portability/role=secondary
```

The actual managed-cluster names can be anything.

## How the control loop works

```text
Git repository
      |
      v
Root Argo CD Application
      |
      v
ACM Placement + GitOpsCluster + ApplicationSet
      |
      v
PlacementDecision selects eligible managed cluster(s)
      |
      v
ApplicationSet creates generated Argo CD Application(s)
      |
      v
OpenShift GitOps deploys the Helm chart
```

A scenario change updates `hub/30-application-placement.yaml`, commits it, and pushes it. The root Argo CD Application reconciles the new Placement. This avoids the common mistake of patching a Git-managed Placement directly, which Argo CD self-heal would immediately reverse.

# Administrator prerequisites

These are platform-level actions and should normally be completed once by an ACM hub cluster administrator.

## 1. ACM hub and imported managed clusters

ACM must already be installed on the hub, and the two destination OpenShift clusters must already be imported.

Verify the hub:

```bash
oc get multiclusterhub -A
```

List managed clusters and their status:

```bash
oc get managedclusters
```

For each destination cluster, confirm:

- `ManagedClusterJoined=True`
- `ManagedClusterConditionAvailable=True`

Detailed check:

```bash
oc get managedcluster <cluster-name> -o yaml
```

The hub's own `local-cluster` resource is not used as a workload destination by this demo.

## 2. Red Hat OpenShift GitOps

Install the Red Hat OpenShift GitOps Operator on the ACM hub. The repository expects the default Argo CD instance and namespace:

```text
openshift-gitops
```

Verify:

```bash
oc get csv -A | grep -i openshift-gitops
oc get deployments -n openshift-gitops
```

The relevant deployments should be available before continuing.

## 3. ACM GitOps integration APIs

Verify that the required APIs exist:

```bash
oc api-resources --api-group=apps.open-cluster-management.io | grep gitopsclusters
oc api-resources --api-group=cluster.open-cluster-management.io | grep -E 'placements|placementdecisions|managedclustersets'
oc api-resources --api-group=argoproj.io | grep -E 'applicationsets|applications'
```

Required resource types:

- `GitOpsCluster`
- `Placement`
- `PlacementDecision`
- `ManagedClusterSet`
- `ManagedClusterSetBinding`
- Argo CD `Application`
- Argo CD `ApplicationSet`

The `GitOpsCluster` controller registers Placement-selected managed clusters with the Argo CD instance. The ApplicationSet cluster-decision generator then consumes the workload PlacementDecision.

## 4. Hub-to-managed-cluster connectivity

This demo uses hub-based OpenShift GitOps in a push model. The Argo CD controllers on the hub must be able to reach the Kubernetes API endpoints of both managed clusters.

Also verify:

- Managed clusters can pull the workload image.
- The hub can reach the Git repository.
- Repository credentials are configured in Argo CD when the repository is private.
- Any corporate proxy, firewall or disconnected registry requirements are already addressed.

## 5. Local command-line tools

The workstation running the helper scripts requires:

```text
oc
git
jq
python3
```

Verify:

```bash
oc version --client
git --version
jq --version
python3 --version
```

## 6. Permissions

The administrator bootstrap requires permission to:

- Create a `ManagedClusterSet`.
- Bind the set into the `openshift-gitops` namespace.
- Label `ManagedCluster` resources.

Creating the `ManagedClusterSetBinding` requires the protected `managedclustersets/bind` permission. Run the bootstrap as a hub cluster administrator or an appropriately delegated administrator.

# Clone and configure the repository

Fork or copy the repository into a Git location controlled by the demo owner, then clone it:

```bash
git clone <your-repository-url>
cd openshift-portability-demo
```

Configure all manifests to use the clone's `origin` URL and current branch:

```bash
./scripts/configure-repository.sh
```

Alternatively, supply them explicitly:

```bash
./scripts/configure-repository.sh \
  https://git.example.com/team/openshift-portability-demo.git \
  main
```

Validate the repository before committing:

```bash
./scripts/validate.sh
```

Commit and push the generated configuration:

```bash
git add .
git commit -m "Configure portability demo repository"
git push
```

The root Argo CD Application cannot deploy successfully until these changes are available in the configured Git repository.

# Administrator bootstrap

Assign the two imported managed clusters to the reusable primary and secondary roles:

```bash
./scripts/bootstrap-demo.sh \
  --primary <primary-managedcluster-name> \
  --secondary <secondary-managedcluster-name>
```

The script performs the following actions:

1. Verifies that you are logged into the ACM hub.
2. Verifies that both named `ManagedCluster` resources exist.
3. Creates the `demo-clusters` ManagedClusterSet.
4. Creates its ManagedClusterSetBinding in `openshift-gitops`.
5. Adds both clusters to the set.
6. Adds the portable `primary` and `secondary` role labels.
7. Verifies the resulting configuration.

When the hub has exactly two non-hub managed clusters, the names can be inferred:

```bash
./scripts/bootstrap-demo.sh
```

The inferred assignment is printed. For a customer demonstration, explicitly naming the primary and secondary clusters is safer and more predictable.

Validate an existing bootstrap without changing anything:

```bash
./scripts/bootstrap-demo.sh --check-only
```

Manual verification:

```bash
oc get managedclusterset demo-clusters
oc get managedclustersetbinding demo-clusters -n openshift-gitops
oc get managedclusters \
  -l cluster.open-cluster-management.io/clusterset=demo-clusters \
  -L demo.portability/role
```

# Deploy the hub-side GitOps resources

Create the root Argo CD Application:

```bash
oc apply -f bootstrap/portability-demo-hub.yaml
```

Run preflight:

```bash
./scripts/preflight.sh
```

`preflight.sh` is a read-only environment validation tool. It checks:

- Repository placeholders have been replaced.
- ACM and OpenShift GitOps APIs are available.
- The `openshift-gitops` namespace exists.
- The ManagedClusterSet and binding exist.
- Exactly two clusters are members of the demo set.
- Primary and secondary roles are assigned.
- Managed clusters are joined and reports their availability.
- Whether the root Argo CD Application has been created.

A failed preflight does not change the environment. It reports the prerequisite or deployment step that is missing.

Watch the full control loop:

```bash
./scripts/watch-demo.sh
```

Or display a single status snapshot:

```bash
./scripts/status.sh
```

Always use the fully qualified Argo CD resource name when checking Applications:

```bash
oc get applications.argoproj.io -n openshift-gitops
```

The short name `application` may resolve to the unrelated `applications.app.k8s.io` API.

# Demo scenarios

## Baseline: primary role

```bash
./scripts/scenario.sh primary
```

Expected result:

- Placement selects the cluster labelled `demo.portability/role=primary`.
- ApplicationSet creates one generated Argo CD Application.
- The workload is deployed to the primary-role cluster.

## Planned move to secondary

```bash
./scripts/scenario.sh secondary
```

The helper copies the secondary Placement scenario into the Git-managed Placement file, commits it, pushes it, refreshes the root Application and waits for reconciliation.

## Return to primary

```bash
./scripts/scenario.sh primary
```

## Active-active deployment

```bash
./scripts/scenario.sh active-active
```

Expected result: the PlacementDecision contains both role-labelled clusters and ApplicationSet generates an Application for each.

## Availability-driven single-cluster failover mode

Activate failover mode:

```bash
./scripts/scenario.sh auto-failover
```

This scenario selects exactly one cluster from the eligible primary and secondary roles. It does not move the application merely because a pod fails. ACM Placement evaluates managed-cluster eligibility, not application health.

The workload Placement intentionally does not tolerate ACM's `unreachable` and `unavailable` `NoSelect` taints. A cluster with one of those taints becomes ineligible and Placement selects another healthy destination.

### Automated taint-based failover test

Simulate failure of the currently selected cluster:

```bash
./scripts/failover.sh
```

The script:

1. Confirms that `auto-failover` is the current Git scenario.
2. Discovers the currently selected destination from the PlacementDecision.
3. Refuses to overwrite a pre-existing unreachable taint, because it could represent a genuine outage.
4. Marks the failure as demo-generated.
5. Applies `cluster.open-cluster-management.io/unreachable:NoSelect`.
6. Waits for the PlacementDecision to select the other eligible cluster.
7. Prints the resulting status and elapsed time.

A cluster name can be supplied as a safety assertion:

```bash
./scripts/failover.sh <currently-selected-managedcluster>
```

The command refuses to proceed if that cluster is not the current destination.

Observe the transition:

```bash
./scripts/watch-demo.sh 2
```

Expected sequence:

1. The selected managed cluster becomes ineligible.
2. ACM recalculates the PlacementDecision.
3. ApplicationSet removes the old generated Application and creates one for the surviving cluster.
4. Argo CD deploys the workload to the new destination.

### Recover the simulated failed cluster

Recover by automatic discovery:

```bash
./scripts/recover.sh
```

Or explicitly:

```bash
./scripts/recover.sh <managedcluster-name>
```

The recovery script removes only a taint marked as demo-generated. It will not remove a genuine ACM outage taint accidentally.

The `Steady` prioritizer may keep the workload on the surviving cluster after recovery. This prevents unnecessary oscillation. Perform a deliberate failback with:

```bash
./scripts/scenario.sh primary
```

### More realistic communication-loss test

For a deeper lab test, the Klusterlet registration and work agents can be stopped temporarily on the selected managed cluster. ACM will eventually mark the cluster unavailable and apply the appropriate taint itself.

This method is slower, affects cluster management, and is less suitable for a live customer demo. Use the automated taint test for presentations.

### Important failover boundaries

During a genuine network partition, hub-based Argo CD can deploy to the surviving cluster but may not be able to prune the old workload from the unreachable cluster until connectivity returns.

Production designs must therefore consider:

- Traffic fencing and split-brain prevention.
- Stateful data replication and consistency.
- Stable global DNS or load balancing.
- Route health checks and traffic draining.
- Recovery-point and recovery-time objectives.

## Remove the workload everywhere

```bash
./scripts/scenario.sh remove
```

# Demonstrating GitOps drift correction

After the workload is healthy, manually change a Git-managed object on a managed cluster, such as the Deployment replica count or ConfigMap content. Argo CD should restore the declared state.

Use this only on the demonstration workload and explain that the correction occurs because automated sync and self-heal are enabled.

# Status tools

Single snapshot:

```bash
./scripts/status.sh
```

Continuously refreshed dashboard:

```bash
./scripts/watch-demo.sh
```

Custom refresh interval in seconds:

```bash
./scripts/watch-demo.sh 5
```

The status tools dynamically discover:

- Cluster-set membership.
- Primary and secondary roles.
- ACM availability.
- ManagedCluster taints.
- Current PlacementDecision.
- Generated Argo CD Applications.
- Argo CD sync and health status.

# Cleanup and retest

## Standard cleanup

```bash
./scripts/cleanup-demo.sh
```

The standard cleanup:

- Commits and pushes the `remove` scenario where possible.
- Removes generated Argo CD Applications.
- Removes the root Application and hub demo resources.
- Removes demo-generated failover taints.
- Retains the ManagedClusterSet, binding and role labels for quick retesting.

## Full administrator reset

```bash
./scripts/cleanup-demo.sh --full
```

The full reset additionally removes:

- ManagedClusterSet membership labels.
- Primary and secondary role labels.
- ManagedClusterSetBinding.
- ManagedClusterSet.

Use `--full` when demonstrating the administrator bootstrap from the beginning.

## End-to-end retest

```bash
# Administrator preparation
./scripts/bootstrap-demo.sh \
  --primary <primary-managedcluster-name> \
  --secondary <secondary-managedcluster-name>

# Repository configuration, when needed
./scripts/configure-repository.sh
./scripts/validate.sh
git add .
git commit -m "Configure portability demo"
git push

# Root deployment
oc apply -f bootstrap/portability-demo-hub.yaml
./scripts/preflight.sh

# Baseline and scenarios
./scripts/scenario.sh primary
./scripts/scenario.sh secondary
./scripts/scenario.sh active-active
./scripts/scenario.sh auto-failover
./scripts/failover.sh
./scripts/recover.sh
./scripts/scenario.sh remove
```

# Repository layout

```text
bootstrap/       Root Argo CD Application
charts/          Portable Helm workload
hub/             GitOpsCluster, Placements and ApplicationSet
prerequisites/   ManagedClusterSet and namespace binding
scripts/         Configuration, validation, scenarios and lifecycle helpers
scripts/lib/     Shared discovery and output functions
docs/            Runbook, presenter guidance and troubleshooting
```

# Other production considerations

- **Private Git:** configure Argo CD repository credentials.
- **Disconnected environments:** mirror the workload image and update Helm values.
- **Argo CD RBAC:** use a dedicated AppProject with constrained repositories, destinations and resource kinds.
- **Secrets:** use an approved external or encrypted secret-management approach.
- **Traffic management:** cluster-local Routes do not provide a stable global application endpoint.
- **Observability:** measure placement, deployment and service recovery time using ACM and application telemetry.
- **Stateful workloads:** use an appropriate storage and DR design; Placement alone is not data mobility.

# Troubleshooting

Start with:

```bash
./scripts/preflight.sh
./scripts/status.sh
```

Useful commands:

```bash
oc get managedclustersets
oc get managedclustersetbindings -n openshift-gitops
oc get managedclusters -L demo.portability/role
oc get placements.cluster.open-cluster-management.io -n openshift-gitops
oc get placementdecisions.cluster.open-cluster-management.io -n openshift-gitops
oc get gitopsclusters.apps.open-cluster-management.io -n openshift-gitops
oc get applicationsets.argoproj.io -n openshift-gitops
oc get applications.argoproj.io -n openshift-gitops
```

See `docs/troubleshooting.md` for detailed fault isolation.
