# Troubleshooting

## `oc get application` reports `applications.app.k8s.io` not found

Use the fully qualified Argo CD CRD:

```bash
oc get applications.argoproj.io -n openshift-gitops
```

## Bootstrap is OutOfSync on ManagedClusterSetBinding

Symptom:

```text
user system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller
is not allowed to bind cluster set demo-clusters
```

Fix:

```bash
oc apply -f prerequisites/clusterset-and-binding.yaml
```

The binding is deliberately excluded from `hub/kustomization.yaml` because it
must be created by a suitably privileged platform administrator.

## GitOpsCluster resolves zero managed clusters

Check membership and binding:

```bash
oc get managedclusters \
  -L cluster.open-cluster-management.io/clusterset \
  -L region

oc get managedclustersetbinding -n openshift-gitops
oc describe placement portability-demo-registered-clusters -n openshift-gitops
```

Both SNO clusters must belong to `demo-clusters` and that set must be bound to
`openshift-gitops`.

## PlacementDecision exists but no generated Application

```bash
oc get applicationsets.argoproj.io portability-demo \
  -n openshift-gitops -o yaml

oc logs -n openshift-gitops \
  deployment/openshift-gitops-applicationset-controller \
  --tail=300
```

Verify that the `acm-placement` ConfigMap exists and that the target Placement
has at least one decision.

## Application exists but destination cluster is unknown

```bash
oc get gitopscluster portability-demo-gitops \
  -n openshift-gitops -o yaml

oc get secrets -n openshift-gitops \
  -l argocd.argoproj.io/secret-type=cluster
```

The registration Placement should select both SNO clusters and the
`GitOpsCluster` should report both as registered.

## Pod prints S2I instructions

The old chart used `registry.access.redhat.com/ubi9/nginx-124`, which is an S2I
builder image. Version 2 uses:

```text
nginxinc/nginx-unprivileged:1.28.1-alpine
```

Confirm the rendered Deployment:

```bash
oc --context cluster1-sno get deployment portability-demo \
  -n portability-demo \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

If the old image remains, verify that the Git change was pushed and hard-refresh
the generated Argo CD Application.

## Pod is in ImagePullBackOff

```bash
oc --context cluster1-sno describe pod \
  -n portability-demo \
  -l app.kubernetes.io/name=portability-demo
```

Confirm that the SNO cluster can reach Docker Hub or mirror the image into an
accessible registry and change `image.repository` and `image.tag` in
`values.yaml`.

## Pod is rejected by SCC

Inspect the event:

```bash
oc --context cluster1-sno get events \
  -n portability-demo \
  --sort-by=.lastTimestamp
```

The chart does not specify a fixed UID and is designed for OpenShift's restricted
SCC. Do not add `runAsUser: 101`; let OpenShift assign a namespace UID.

## Route returns 503

```bash
oc --context cluster1-sno get deploy,pod,svc,endpoints,route \
  -n portability-demo

oc --context cluster1-sno describe deployment portability-demo \
  -n portability-demo
```

The Service target port is the named port `http`, which maps to container port
`8080`.

## HTML changed but the pod did not restart

The Deployment includes a checksum of `configmap.yaml` in the pod-template
annotations. Confirm that the new commit reached the generated Application:

```bash
oc get applications.argoproj.io portability-demo-cluster1-sno \
  -n openshift-gitops \
  -o jsonpath='{.status.sync.revision}{"\n"}'
```
