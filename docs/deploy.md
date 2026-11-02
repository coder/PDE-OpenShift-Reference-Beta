# Deploy & reset runbook

> Scaffold — the commands below are the intended contract; targets fill in across
> Phases 1–7. Goal: **one‑command, idempotent, no hand‑run scripts, no code↔live drift.**

## Prerequisites (provided at deploy time — never committed, per D5)
- AWS creds for sandbox **342934376218** (`AWS_PROFILE` / SSO), region `us-east-1`.
- `oc`, `aws`, `terraform` on PATH (`make preflight` checks).
- A **Red Hat pull secret** (for RHOAI/RHBK operator images).
- A **Coder license** key (needed at the air‑gap/Agents phase).
- `base_domain` for the new DNS (default `pde.coderdemo.io`; see `terraform/terraform.tfvars.example`).

## Deploy
```bash
make preflight                 # tooling + access checks
make deploy                    # connected mode (default)
make deploy MODE=airgap        # air-gap-ready mode
make status                    # Argo apps + InferenceService health
```
What `deploy` will do (phased):
1. **P1** cluster prereqs (terraform) + operator subscriptions (GitOps, cert‑manager, RHOAI, ESO, CNPG).
2. **P2** Keycloak (realm `demo`, secrets generated in‑cluster) + in‑cluster Git + committed Argo RBAC.
3. **P3** Coder (Helm via GitOps), OIDC → Keycloak, routes/TLS, CNPG Postgres.
4. **P4** RHOAI ServingRuntime + InferenceService (Qwen2.5‑7B on A10G) + AI Gateway wiring.
5. **P5** workspace templates from internal‑registry images; validate a Coder Agents run.
6. **P6** (airgap) egress default‑deny + internal‑registry‑only + Coder air‑gapped bundle.

## Reset (between demos)
```bash
make reset     # delete demo workspaces/chats + re-seed Git projects + re-seed identity; infra untouched
```

## Teardown
```bash
make destroy   # terraform destroy (+ openshift-install destroy)
```

## Acceptance (definition of done — P7)
Fresh account → `make deploy` → SSO‑gated Coder, a workspace from an internal‑registry
image, a Coder Agents chat driving the in‑cluster RHOAI model; `make deploy MODE=airgap`
denies workspace egress yet the agent still answers from in‑cluster; `make reset`
returns to clean. No hand‑run scripts; no code↔live drift.
