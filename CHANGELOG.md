# Changelog

## 4.0.0

- Changed Day-2 scenario switching from direct live Placement updates to Git commits and pushes.
- Added hard refresh and PlacementDecision verification after scenario changes.
- Added `cleanup-demo.sh` for generated Application pruning, hub cleanup and managed-cluster namespace reset.
- Added optional full cleanup of ManagedClusterSet prerequisites.
- Documented Argo CD API-name ambiguity and end-to-end retesting.

## 3.0.0

- Expanded the project into a Day-2 Operations and Application Mobility demo.
- Added administrator bootstrap and check-only validation.
- Added deterministic primary/secondary moves, active-active expansion, availability-driven failover mode and clean removal.
- Added consolidated status reporting, operator runbook and presenter script.
- Documented production integration considerations and the boundary between stateless mobility and stateful DR.

## 2.0.0

- Replaced the S2I builder image with an OpenShift-compatible unprivileged NGINX runtime.
- Added probes, restricted security settings, rolling updates and prerequisite separation.
