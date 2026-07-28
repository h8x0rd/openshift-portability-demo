# OpenShift Application Portability Demo

A GitHub-ready demonstration of moving one application between two AWS-hosted
OpenShift Single Node OpenShift (SNO) clusters using Red Hat Advanced Cluster
Management (ACM), OpenShift GitOps, ACM `Placement`, and an Argo CD
`ApplicationSet`.

## Demo environment

This repository is preconfigured for the following ACM managed clusters:

| Managed cluster | AWS region | ACM labels |
|---|---|---|
| `cluster1-sno` | `eu-west-3` | `region=eu-west-3`, `cloud=Amazon`, `vendor=OpenShift` |
| `cluster2-sno` | `eu-west-2` | `region=eu-west-2`, `cloud=Amazon`, `vendor=OpenShift` |
| `local-cluster` | ACM hub | `cloud=Other`, `vendor=OpenShift` |

The hub is deliberately excluded from workload placement because the
application placement requires both `cloud=Amazon` and one of the configured
AWS region labels.

## What the audience sees

The demo application renders a visual cluster identity page showing:

- the ACM managed-cluster name
- the AWS region
- the application version
- the GitOps-managed health message
- the same application deployed to one or both clusters

The workload is defined once as a Helm chart. ACM controls where it runs.
OpenShift GitOps continuously reconciles the selected destinations.

## Architecture

```text
GitHub repository
  ├── hub/                         Fleet registration and application placement
  └── charts/portability-demo/     One portable Helm application
             |
             v
OpenShift GitOps on the ACM hub
             |
             +--> ACM Placement --> PlacementDecision
                         |
                         v
                 ApplicationSet generator
                    /            \
                   v              v
       cluster1-sno             cluster2-sno
       eu-west-3                eu-west-2
```

## Important readiness checkpoint

Your current cluster output shows both SNO clusters as `AVAILABLE=Unknown`.
Do not continue with the GitOps deployment until they report `JOINED=True` and
`AVAILABLE=True`.

Check repeatedly with:

```bash
oc get managedclusters \
  -L region \
  -L cloud \
  -L vendor
```

The expected state is similar to:

```text
NAME            JOINED   AVAILABLE   REGION      CLOUD    VENDOR
cluster1-sno    True     True        eu-west-3   Amazon   OpenShift
cluster2-sno    True     True        eu-west-2   Amazon   OpenShift
local-cluster   True     True                    Other    OpenShift
```

If either SNO remains `Unknown`, inspect it before continuing:

```bash
oc describe managedcluster cluster1-sno
oc describe managedcluster cluster2-sno

oc get klusterletaddonconfig -A
oc get managedclusteraddon -A
```

Also verify that each cluster has completed import and can reach the ACM hub.

## Repository layout

```text
openshift-portability-demo/
├── README.md
├── charts/
│   └── portability-demo/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values-cluster1-sno.yaml
│       ├── values-cluster2-sno.yaml
│       └── templates/
├── bootstrap/
│   └── portability-demo-hub.yaml
├── hub/
│   ├── 00-clusterset-binding.yaml
│   ├── 10-registration-placement.yaml
│   ├── 20-gitops-cluster.yaml
│   ├── 30-application-placement.yaml
│   ├── 40-application-set.yaml
│   ├── placement-scenarios/
│   │   ├── eu-west-3.yaml
│   │   ├── eu-west-2.yaml
│   │   └── both-regions.yaml
│   └── kustomization.yaml
├── scripts/
│   ├── configure-repository.sh
│   ├── move.sh
│   ├── expand.sh
│   └── clear.sh
└── docs/
    ├── demo-script.md
    └── troubleshooting.md
```

## How cluster-specific display values work

There is still only one application chart. The ApplicationSet dynamically loads
one small values file using the selected ACM cluster name:

```yaml
helm:
  valueFiles:
    - 'values-{{name}}.yaml'
```

Therefore:

```text
cluster1-sno -> values-cluster1-sno.yaml -> eu-west-3
cluster2-sno -> values-cluster2-sno.yaml -> eu-west-2
```

These files contain display metadata only. The Deployments, Services, Routes,
and application content remain shared.

## Prerequisites

- ACM hub with `cluster1-sno` and `cluster2-sno` successfully imported.
- Both SNO clusters show `JOINED=True` and `AVAILABLE=True`.
- OpenShift GitOps installed on the ACM hub.
- ACM and OpenShift GitOps integration components available.
- `oc`, `git`, `bash`, and cluster-admin access for initial setup.
- A `ManagedClusterSet` containing both SNO clusters.
- The `ManagedClusterSet` bound to the `openshift-gitops` namespace.
- Network connectivity from the hub/GitOps components to both managed clusters.

## 1. Prepare the GitHub repository

Extract this archive, create a GitHub repository, and replace the placeholder
repository URL:

```bash
cd openshift-portability-demo

./scripts/configure-repository.sh \
  https://github.com/YOUR_ORG/openshift-portability-demo.git
```

Commit and push:

```bash
git init
git add .
git commit -m "Initial AWS SNO portability demo"
git branch -M main
git remote add origin \
  https://github.com/YOUR_ORG/openshift-portability-demo.git
git push -u origin main
```

## 2. Verify the existing ACM labels

No custom region labels are required. Confirm the labels already present:

```bash
oc get managedcluster cluster1-sno \
  -o jsonpath='{.metadata.labels.region}{"\n"}'

oc get managedcluster cluster2-sno \
  -o jsonpath='{.metadata.labels.region}{"\n"}'
```

Expected output:

```text
eu-west-3
eu-west-2
```

Also verify the cloud and vendor labels:

```bash
oc get managedclusters -L region -L cloud -L vendor
```

## 3. Configure the ManagedClusterSet binding

Edit:

```text
hub/00-clusterset-binding.yaml
```

Set `spec.clusterSet` to the `ManagedClusterSet` containing `cluster1-sno` and
`cluster2-sno`:

```yaml
spec:
  clusterSet: demo-clusters
```

Check cluster-set membership with:

```bash
oc get managedclusterset
oc get managedclusters --show-labels
```

## 4. Configure the GitOpsCluster hub reference

The supplied manifest assumes the ACM hub managed-cluster name is:

```text
local-cluster
```

Verify it:

```bash
oc get managedcluster local-cluster
```

The relevant section in `hub/20-gitops-cluster.yaml` is:

```yaml
spec:
  argoServer:
    cluster: local-cluster
    argoNamespace: openshift-gitops
```

## 5. Review the registration placement

`hub/10-registration-placement.yaml` registers only AWS OpenShift clusters in
the two demo regions with Argo CD:

```yaml
matchExpressions:
  - key: vendor
    operator: In
    values: [OpenShift]
  - key: cloud
    operator: In
    values: [Amazon]
  - key: region
    operator: In
    values:
      - eu-west-3
      - eu-west-2
```

This excludes `local-cluster` because it has `cloud=Other` and no AWS region.

## 6. Bootstrap GitOps management of the hub resources

The default application destination is `eu-west-3`, which selects
`cluster1-sno`.

After the repository has been pushed, create the bootstrap Argo CD Application:

```bash
oc apply -f bootstrap/portability-demo-hub.yaml
```

The bootstrap Application continuously reconciles the `hub/` directory. This
means later placement commits are applied automatically after `git push`.

For troubleshooting or a non-GitOps bootstrap, the same resources can also be
applied directly:

```bash
oc apply -k hub
```

Confirm the bootstrap and hub resources:

```bash
oc get application portability-demo-hub -n openshift-gitops
```

Then confirm:

```bash
oc get managedclustersetbinding -n openshift-gitops
oc get placement -n openshift-gitops
oc get gitopscluster -n openshift-gitops
oc get applicationset -n openshift-gitops
```

Check the registration placement decision:

```bash
oc get placementdecision -n openshift-gitops \
  -l cluster.open-cluster-management.io/placement=portability-demo-registered-clusters \
  -o yaml
```

Check the application placement decision:

```bash
oc get placementdecision -n openshift-gitops \
  -l cluster.open-cluster-management.io/placement=portability-demo-targets \
  -o yaml
```

The initial application decision should contain:

```text
cluster1-sno
```

## 7. Verify Argo CD cluster registration

Check the generated Argo CD cluster secrets:

```bash
oc get secrets -n openshift-gitops \
  -l argocd.argoproj.io/secret-type=cluster
```

Then inspect the generated application:

```bash
oc get applications -n openshift-gitops \
  -l demo.portability/application=portability-demo
```

The initial application should be named approximately:

```text
portability-demo-cluster1-sno
```

## Demo method A: fully Git-driven placement

This is the recommended presentation because the location change itself is
stored in Git.

### Start in eu-west-3

Copy the `eu-west-3` scenario over the active placement:

```bash
cp hub/placement-scenarios/eu-west-3.yaml \
  hub/30-application-placement.yaml

git add hub/30-application-placement.yaml
git commit -m "Place application in eu-west-3"
git push
```

### Move to eu-west-2

```bash
cp hub/placement-scenarios/eu-west-2.yaml \
  hub/30-application-placement.yaml

git add hub/30-application-placement.yaml
git commit -m "Move application to eu-west-2"
git push
```

ACM should change the placement decision from:

```text
cluster1-sno
```

to:

```text
cluster2-sno
```

ApplicationSet then removes the old Argo CD Application and creates:

```text
portability-demo-cluster2-sno
```

### Expand to both regions

```bash
cp hub/placement-scenarios/both-regions.yaml \
  hub/30-application-placement.yaml

git add hub/30-application-placement.yaml
git commit -m "Expand application across both AWS regions"
git push
```

The PlacementDecision should now contain both:

```text
cluster1-sno
cluster2-sno
```

## Demo method B: fast live placement changes

The helper scripts patch the live ACM Placement. They are useful for a quick
presentation, but these changes are not persisted in Git. Because the bootstrap
Application continuously manages `hub/`, self-heal can revert a live patch back
to the value stored in Git. Temporarily disable automated self-heal or use the
Git-driven method for a predictable presentation.

### Move to cluster1-sno in eu-west-3

```bash
./scripts/move.sh eu-west-3
```

### Move to cluster2-sno in eu-west-2

```bash
./scripts/move.sh eu-west-2
```

### Expand to both SNO clusters

```bash
./scripts/expand.sh
```

### Remove all destinations

```bash
./scripts/clear.sh
```

Restore the default Git configuration with:

```bash
oc apply -f hub/30-application-placement.yaml
```

## Watch the relocation live

Use one terminal for the ACM PlacementDecision:

```bash
watch -n 2 'oc get placementdecision -n openshift-gitops \
  -l cluster.open-cluster-management.io/placement=portability-demo-targets \
  -o custom-columns=DECISION:.metadata.name,CLUSTERS:.status.decisions[*].clusterName'
```

Use a second terminal for Argo CD Applications:

```bash
watch -n 2 'oc get applications -n openshift-gitops \
  -l demo.portability/application=portability-demo \
  -o custom-columns=APPLICATION:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,DESTINATION:.spec.destination.server'
```

Use a third terminal to display managed-cluster state:

```bash
watch -n 3 'oc get managedclusters -L region -L cloud -L vendor'
```

## Suggested live-demo flow

1. Show `cluster1-sno` in `eu-west-3` and `cluster2-sno` in `eu-west-2` in ACM.
2. Confirm both clusters are `JOINED=True` and `AVAILABLE=True`.
3. Show the repository contains one Helm chart.
4. Show the active Placement selecting `region=eu-west-3`.
5. Open the application route on `cluster1-sno`.
6. Point out that the page displays `cluster1-sno` and `eu-west-3`.
7. Change the Git placement scenario to `eu-west-2` and push.
8. Watch the PlacementDecision change to `cluster2-sno`.
9. Watch Argo CD prune the old generated Application and create the new one.
10. Open the route on `cluster2-sno` and show `cluster2-sno` and `eu-west-2`.
11. Change to the `both-regions` scenario.
12. Show both Argo CD Applications healthy simultaneously.
13. Change the shared application version in `values.yaml`, commit once, and
    show both clusters receive the update.

## Presenter message

> The application team maintains one portable application definition. ACM
> translates business placement intent into a cluster decision, and OpenShift
> GitOps reconciles that decision. Moving from Paris to London, or expanding to
> both regions, does not require copying or rewriting the application.

## SNO-specific considerations

These clusters are Single Node OpenShift installations:

- Multiple application replicas still run on the same physical or virtual node.
- Do not describe two replicas on one SNO as node-level high availability.
- The demo demonstrates cluster-level and regional portability.
- Keep resource requests small to avoid unnecessary pressure on the SNO node.
- A stateless application is preferable for the first demonstration.

## Stateful application scope

This repository demonstrates declarative workload redeployment and placement.
It does not automatically move:

- persistent volume data
- database state
- external DNS
- user sessions
- message queues
- secrets held outside GitOps

A production stateful portability demonstration would additionally require
storage or database replication, backup and restore, secret synchronization,
and global traffic management.

## Troubleshooting

### No PlacementDecision

```bash
oc describe placement portability-demo-targets -n openshift-gitops
oc get managedclusters -L region -L cloud -L vendor
oc get managedclustersetbinding -n openshift-gitops
```

Confirm that the SNO clusters belong to the `ManagedClusterSet` bound into the
`openshift-gitops` namespace.

### Clusters remain AVAILABLE=Unknown

```bash
oc describe managedcluster cluster1-sno
oc describe managedcluster cluster2-sno
oc get managedclusteraddon -A
```

Resolve cluster import, connectivity, certificate, or add-on problems before
troubleshooting ApplicationSet.

### PlacementDecision exists but no Argo CD Application

```bash
oc get applicationset portability-demo -n openshift-gitops -o yaml
oc get gitopscluster portability-demo-gitops -n openshift-gitops -o yaml
oc get secrets -n openshift-gitops \
  -l argocd.argoproj.io/secret-type=cluster
```

### Application cannot load its values file

The ApplicationSet expects these exact filenames:

```text
values-cluster1-sno.yaml
values-cluster2-sno.yaml
```

The filenames must remain aligned with the ACM managed-cluster names.
