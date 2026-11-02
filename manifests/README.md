# manifests/
Plain Kubernetes/OpenShift resources referenced by the Argo apps, one subdir per app,
plus air-gap overlays (egress-deny NetworkPolicies, internal-registry-only). Secrets
are generated in-cluster (ESO `Password` generators) or operator-managed — **never
values in git** (D5).
