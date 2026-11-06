# Deploy & reset runbook

> Scaffold — the commands below are the intended contract; targets fill in across
> Phases 1–7. Goal: **one‑command, idempotent, no hand‑run scripts, no code↔live drift.**

## Prerequisites (provided at deploy time — never committed, per D5)
- AWS creds for the target account **`<AWS_ACCOUNT_ID>`** (`AWS_PROFILE` / SSO), region `us-east-1` — the account is supplied at deploy time, never committed.
- `oc`, `aws`, `terraform` on PATH (`task preflight` checks).
- A **Red Hat pull secret** (for RHOAI/RHBK operator images).
- A **Coder license** key (needed at the air‑gap/Agents phase).
- `base_domain` for the new DNS (default `rh-pde.coderdemo.io`; see `terraform/terraform.tfvars.example`).

## Deploy
```bash
task preflight                 # tooling + access checks
task deploy                    # connected mode (default)
task deploy MODE=airgap        # air-gap-ready mode
task status                    # Argo apps + InferenceService health
```
What `deploy` will do (phased):
1. **P1** cluster prereqs (terraform) + operator subscriptions (GitOps, cert‑manager, RHOAI, ESO, CNPG).
2. **P2** Keycloak (realm `demo`, secrets generated in‑cluster) + in‑cluster Git + committed Argo RBAC.
3. **P3** Coder (Helm via GitOps), OIDC → Keycloak, routes/TLS, CNPG Postgres.
4. **P4** RHOAI ServingRuntime + InferenceService (Qwen2.5‑7B on A10G) + AI Gateway wiring.
5. **P5** workspace templates from internal‑registry images; validate a Coder Agents run.
6. **P6** (airgap) egress default‑deny + internal‑registry‑only + Coder air‑gapped bundle.

## Credentials (retrieving the generated demo logins)
Per **D5**, no secret is ever committed. The demo personas' passwords are
generated **in‑cluster** at deploy time (ESO `Password` generators) and live
only in `Secret/keycloak-realm-secrets` (ns `keycloak`); Keycloak itself stores
only hashes. Retrieve the human logins — the demo team needs these — with:
```bash
task creds     # personas (alice/bob/demoadm) + Keycloak admin console, read live
```
`task creds` reads straight from the cluster and prints nothing to disk/git.
It requires **cluster‑admin** (`kube:admin` at install; `demoadm` works once the
realm is up). The machine OIDC client secrets (`*_client_secret`) are wired
automatically and are intentionally **not** printed. Override the namespace with
`task creds KEYCLOAK_NS=<ns>` if needed.

## Reset (between demos)
```bash
task reset     # delete demo workspaces/chats + re-seed Git projects + re-seed identity; infra untouched
```

## Teardown
```bash
task destroy   # terraform destroy (+ openshift-install destroy)
```

## Acceptance (definition of done — P7)
Fresh account → `task deploy` → SSO‑gated Coder, a workspace from an internal‑registry
image, a Coder Agents chat driving the in‑cluster RHOAI model; `task deploy MODE=airgap`
denies workspace egress yet the agent still answers from in‑cluster; `task reset`
returns to clean. No hand‑run scripts; no code↔live drift.
