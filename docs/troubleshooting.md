# Troubleshooting

## No PlacementDecision

Check:

```bash
oc describe placement portability-demo-targets -n openshift-gitops
oc get managedclusters --show-labels
oc get managedclustersetbinding -n openshift-gitops
```

The selected clusters must belong to the bound `ManagedClusterSet`.

## PlacementDecision exists but no Application

Check:

```bash
oc get applicationset portability-demo -n openshift-gitops -o yaml
oc logs -n openshift-gitops deploy/openshift-gitops-applicationset-controller
```

Confirm that the ACM placement generator ConfigMap exists and that the
ApplicationSet controller has access to PlacementDecision resources.

## Application exists but cluster is unknown to Argo CD

Check:

```bash
oc get gitopscluster portability-demo-gitops -n openshift-gitops -o yaml
oc get secret -n openshift-gitops   -l argocd.argoproj.io/secret-type=cluster
```

Confirm the registration Placement includes the cluster and that the
`GitOpsCluster` reports successful reconciliation.

## Cluster identity does not render

Confirm that the generated Argo CD Application contains the expected Helm
parameters:

```bash
oc get application -n openshift-gitops   -l demo.portability/application=portability-demo -o yaml
```

The cluster name and API server are supplied by the ACM placement generator.
Region and environment are deliberately static in the starter manifest. For
richer per-cluster metadata, add a Git generator and combine it with the
placement generator by using an ApplicationSet matrix generator.

## Route returns 503

Check:

```bash
oc -n portability-demo get deploy,pod,svc,route
oc -n portability-demo describe deploy portability-demo
```

Confirm the selected UBI nginx image tag is available in your environment.
