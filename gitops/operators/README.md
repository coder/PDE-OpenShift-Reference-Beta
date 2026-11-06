# gitops/operators/
OLM Subscriptions applied by the bootstrap step of `task deploy` **before** the Argo
root app, because their CRDs must exist before `gitops/apps/` can sync. Order-prefixed.
No secret values here (D5). Channels pinned to the live catalog (verified 2026-11-02).

| File | Operator | Source | Channel |
|---|---|---|---|
| 00 | OpenShift GitOps (Argo CD) | redhat-operators | latest |
| 10 | cert-manager | redhat-operators | stable-v1 |
| 20 | CloudNativePG | certified-operators | stable-v1 |
| 30 | External Secrets Operator | redhat-operators | stable-v1 |
| 40 | OpenShift AI (RHOAI, rhods-operator) | redhat-operators | stable-3.x |
| 50 | Node Feature Discovery | redhat-operators | stable |
| 60 | NVIDIA GPU Operator | certified-operators | v26.7 |
