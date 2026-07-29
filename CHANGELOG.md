# Changelog

## 5.0.0 - 2026-07-29

### Added
- Dynamic primary and secondary role discovery through ManagedCluster labels
- Automatic repository URL and target revision configuration
- `failover.sh`, `recover.sh`, `preflight.sh`, and `watch-demo.sh`
- Failover walkthrough directly beneath the availability-driven scenario
- Generic cleanup that discovers clusters from the ManagedClusterSet

### Changed
- Removed all embedded cluster names, AWS regions and personal repository URLs
- Replaced region selectors with portable `demo.portability/role` selectors
- Removed per-cluster Helm values files
- Updated workload and chart version to 5.0.0

### Compatibility
- Requires ACM Placement, GitOpsCluster, OpenShift GitOps ApplicationSet support, `jq`, `git`, `oc`, and `python3`.
