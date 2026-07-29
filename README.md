# OpenShift Application Portability Demo

A GitHub-ready demonstration of moving one application between two AWS-hosted
Single Node OpenShift clusters using Red Hat Advanced Cluster Management (ACM),
OpenShift GitOps, ACM `Placement`, `GitOpsCluster`, and an Argo CD
`ApplicationSet`.

## Demo environment

| Managed cluster | AWS region | Relevant labels |
|---|---|---|
| `cluster1-sno` | `eu-west-3` | `region=eu-west-3`, `cloud=Amazon`, `vendor=OpenShift` |
| `cluster2-sno` | `eu-west-2` | `region=eu-west-2`, `cloud=Amazon`, `vendor=OpenShift` |
| `local-cluster` | ACM hub | `cloud=Other`, `vendor=OpenShift` |

The hub is excluded because workload placement requires `cloud=Amazon` and one
of the two configured region labels.

## What changed in version 2

- Replaced the Red Hat S2I NGINX builder image with the unprivileged NGINX
  runtime image `nginxinc/nginx-unprivileged:1.28.1-alpine`.
- Runs on container port `8080` under OpenShift's restricted security model.
- Added startup, readiness, and liveness probes.
- Added an explicit non-root security context and dropped all Linux capabilities.
- Disabled service-account token mounting for the demo pod.
- Added a ConfigMap checksum so page changes trigger a rolling deployment.
- Added a Helm test pod.
- Moved the protected `ManagedClusterSetBinding` out of Argo CD management.
- Added validation and troubleshooting commands using fully qualified Argo CD
  resource names such as `applications.argoproj.io`.

## Architecture

```text
GitHub
  ├── prerequisites/        One-time platform-administrator resources
  ├── hub/                  Placement, GitOpsCluster, ApplicationSet
  └── charts/               One portable Helm workload
          |
          v
OpenShift GitOps on local-cluster
          |
          +--> ACM Placement --> PlacementDecision
                                   |
                                   v
                              ApplicationSet
                               /          \
                              v            v
                     cluster1-sno     cluster2-sno
                      eu-west-3        eu-west-2
```

## Repository layout

```text
openshift-portability-demo/
├── bootstrap/
│   └── portability-demo-hub.yaml
├── prerequisites/
│   └── clusterset-and-binding.yaml
├── hub/
│   ├── 10-registration-placement.yaml
│   ├── 20-gitops-cluster.yaml
│   ├── 30-application-placement.yaml
│   ├── 40-application-set.yaml
│   ├── placement-scenarios/
│   └── kustomization.yaml
├── charts/portability-demo/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-cluster1-sno.yaml
│   ├── values-cluster2-sno.yaml
│   └── templates/
├── scripts/
└── docs/
```

## Prerequisites

- ACM hub with both SNO clusters imported.
- OpenShift GitOps installed in `openshift-gitops` on the hub.
- ACM GitOps integration CRDs available.
- Cluster-admin access for the one-time cluster-set preparation.
- `oc`, `git`, and `bash`.
- `helm` is recommended for local linting.

Both SNO clusters should be joined and available:

```bash
oc get managedclusters -L region -L cloud -L vendor
```

Expected:

```text
NAME            JOINED   AVAILABLE   REGION      CLOUD    VENDOR
cluster1-sno    True     True        eu-west-3   Amazon   OpenShift
cluster2-sno    True     True        eu-west-2   Amazon   OpenShift
local-cluster   True     True                    Other    OpenShift
```

## 1. Configure your Git repository

```bash
cd openshift-portability-demo

./scripts/configure-repository.sh \
  https://github.com/h8x0rd/openshift-portability-demo.git
```

Confirm that no placeholder remains:

```bash
grep -R "YOUR_ORG" bootstrap hub charts || true
```

Commit and push:

```bash
git init
git add .
git commit -m "Deploy OpenShift portability demo v2"
git branch -M main
git remote add origin \
  https://github.com/h8x0rd/openshift-portability-demo.git
git push -u origin main
```

For an existing clone, simply commit the replaced files and push them.

## 2. Prepare the ManagedClusterSet as cluster administrator

ACM protects cluster-set binding through the `managedclustersets/bind`
subresource. The Argo CD application-controller is intentionally not granted
that permission by this repository.

Apply the platform prerequisite manually:

```bash
oc apply -f prerequisites/clusterset-and-binding.yaml
```

Assign both SNO clusters to the set:

```bash
oc label managedcluster cluster1-sno \
  cluster.open-cluster-management.io/clusterset=demo-clusters \
  --overwrite

oc label managedcluster cluster2-sno \
  cluster.open-cluster-management.io/clusterset=demo-clusters \
  --overwrite
```

Verify:

```bash
oc get managedclusters \
  -L cluster.open-cluster-management.io/clusterset \
  -L region

oc get managedclustersetbinding demo-clusters \
  -n openshift-gitops
```

## 3. Validate the repository

```bash
./scripts/validate.sh
```

When Helm is installed, the script also performs `helm lint` and a rendered
chart check. When `oc` is installed, it renders the hub Kustomization.

## 4. Bootstrap OpenShift GitOps

```bash
oc apply -f bootstrap/portability-demo-hub.yaml
```

Always use the qualified Argo CD resource name because `application` can resolve
to the unrelated `applications.app.k8s.io` API:

```bash
oc get applications.argoproj.io \
  portability-demo-hub \
  -n openshift-gitops
```

Watch the bootstrap status:

```bash
watch -n 3 'oc get applications.argoproj.io \
  portability-demo-hub -n openshift-gitops \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
```

Expected:

```text
portability-demo-hub   Synced   Healthy
```

## 5. Confirm the ACM/GitOps chain

Registration placement should resolve both SNO clusters:

```bash
oc get placementdecision \
  -n openshift-gitops \
  -l cluster.open-cluster-management.io/placement=portability-demo-registered-clusters \
  -o jsonpath='{range .items[*].status.decisions[*]}{.clusterName}{"\n"}{end}'
```

Expected:

```text
cluster1-sno
cluster2-sno
```

The initial workload placement selects `eu-west-3`:

```bash
oc get placementdecision \
  -n openshift-gitops \
  -l cluster.open-cluster-management.io/placement=portability-demo-targets \
  -o jsonpath='{range .items[*].status.decisions[*]}{.clusterName}{"\n"}{end}'
```

Expected:

```text
cluster1-sno
```

Confirm Argo CD cluster registration:

```bash
oc get secrets \
  -n openshift-gitops \
  -l argocd.argoproj.io/secret-type=cluster
```

Confirm generated Applications:

```bash
oc get applications.argoproj.io \
  -n openshift-gitops
```

Expected initially:

```text
portability-demo-hub
portability-demo-cluster1-sno
```

## 6. Validate the workload on cluster1-sno

Use a kubeconfig context that points at `cluster1-sno`:

```bash
oc --context cluster1-sno get deploy,pod,svc,route \
  -n portability-demo
```

Watch the rollout:

```bash
oc --context cluster1-sno rollout status \
  deployment/portability-demo \
  -n portability-demo
```

Get the URL:

```bash
oc --context cluster1-sno get route portability-demo \
  -n portability-demo \
  -o jsonpath='https://{.spec.host}{"\n"}'
```

The pod now uses a runtime web-server image. It should not print the S2I
instructions seen with `ubi9/nginx-124`.

## 7. Move the application to eu-west-2

The recommended demonstration is Git-driven:

```bash
cp hub/placement-scenarios/eu-west-2.yaml \
  hub/30-application-placement.yaml

git add hub/30-application-placement.yaml
git commit -m "Move portability demo to eu-west-2"
git push
```

Watch ACM and Argo CD:

```bash
watch -n 3 '
echo "=== TARGETS ==="
oc get placementdecision -n openshift-gitops \
  -l cluster.open-cluster-management.io/placement=portability-demo-targets \
  -o custom-columns=DECISION:.metadata.name,CLUSTERS:.status.decisions[*].clusterName

echo
echo "=== APPLICATIONS ==="
oc get applications.argoproj.io -n openshift-gitops \
  -l demo.portability/application=portability-demo \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
'
```

The generated Application for `cluster1-sno` is pruned and the same chart is
deployed to `cluster2-sno`.

## 8. Expand to both AWS regions

```bash
cp hub/placement-scenarios/both-regions.yaml \
  hub/30-application-placement.yaml

git add hub/30-application-placement.yaml
git commit -m "Run portability demo in both AWS regions"
git push
```

Expected generated Applications:

```text
portability-demo-cluster1-sno
portability-demo-cluster2-sno
```

## Cluster-specific display values

The ApplicationSet selects a small values file based on the ACM cluster name:

```yaml
valueFiles:
  - 'values-{{ .name }}.yaml'
```

This maps:

```text
cluster1-sno -> values-cluster1-sno.yaml -> eu-west-3
cluster2-sno -> values-cluster2-sno.yaml -> eu-west-2
```

The workload definition remains shared.

## Runtime and security design

The web page is mounted from a ConfigMap into:

```text
/usr/share/nginx/html/index.html
```

The runtime listens on port `8080` and the pod:

- runs as non-root without pinning a UID
- drops all capabilities
- disables privilege escalation
- uses `RuntimeDefault` seccomp
- does not mount a Kubernetes API token
- has CPU and memory requests and limits
- uses startup, readiness, and liveness probes

This is intentionally a stateless portability demonstration. It demonstrates
fleet placement and GitOps reconciliation, not stateful disaster recovery.

## Useful diagnostics

```bash
oc describe applications.argoproj.io portability-demo-hub \
  -n openshift-gitops

oc get applicationsets.argoproj.io portability-demo \
  -n openshift-gitops -o yaml

oc get gitopscluster portability-demo-gitops \
  -n openshift-gitops -o yaml

oc get placements,placementdecisions \
  -n openshift-gitops

oc logs -n openshift-gitops \
  deployment/openshift-gitops-applicationset-controller \
  --tail=200
```

See `docs/troubleshooting.md` for symptom-based diagnostics.
