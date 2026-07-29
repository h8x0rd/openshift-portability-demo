# Changelog

## 2.0.0

- Replaced the S2I NGINX builder image with an unprivileged runtime image.
- Added OpenShift-compatible pod and container security contexts.
- Added startup, readiness, and liveness probes.
- Added ConfigMap checksum-triggered rolling updates.
- Added Helm test and chart notes.
- Separated ManagedClusterSet and ManagedClusterSetBinding into a privileged
  prerequisite step.
- Updated ACM/GitOps diagnostics and fully qualified Argo CD commands.
- Preconfigured cluster identities for cluster1-sno/eu-west-3 and
  cluster2-sno/eu-west-2.
