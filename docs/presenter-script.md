# Presenter Script

1. **Intent:** “The only deployment decision is expressed as a Placement. We are not copying manifests between clusters.”
2. **Baseline:** Run `./scripts/status.sh`, show one decision and one generated Application.
3. **Identity:** Open the app Route and show the live cluster/region identity.
4. **Mobility:** Run `./scripts/scenario.sh secondary`; narrate PlacementDecision → ApplicationSet → Argo CD.
5. **Scale-out:** Run `./scripts/scenario.sh active-active`; show two Applications from one source.
6. **Day-2 rollout:** Commit a message/version change and show rolling reconciliation.
7. **Drift:** Make a harmless manual change, then show self-heal.
8. **Failover:** Use `auto-failover` in a lab and explain health detection and RTO components.
9. **Guardrail:** State clearly that the workload is stateless and that persistent-data DR needs ODF/VolSync and DRPlacementControl.
10. **Close:** “We changed placement intent; ACM and GitOps performed the fleet operations.”
