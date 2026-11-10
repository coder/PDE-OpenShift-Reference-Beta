# Deploy & reset runbook

Goal: **one‑command in‑cluster deploy, idempotent, no code↔live drift.** The
repo brings the *desired state*; this runbook covers standing up a fresh AWS
account end‑to‑end. Nothing secret is committed (D5).

## 0. Fresh-account prerequisites (one-time, out of `task`)
1. **AWS quotas** — request **G/VT instance vCPU** quota (for `g5.2xlarge` A10G;
   0 by default) plus standard vCPU for the OCP control/worker nodes; check
   EIP/VPC/NAT quotas for an IPI install.
2. **DNS** — create + delegate the Route53 public zone for `base_domain`
   (`cd terraform && terraform apply -target=aws_route53_zone.base`, then add the
   output NS records to the parent `coderdemo.io` zone).
3. **Red Hat pull secret** — from console.redhat.com; used as the cluster global
   pull secret at install (for `registry.redhat.io`: RHOAI, RHBK, ose‑cli, UBI).
4. **GHCR images** — the `build-images` workflow pushes the workspace images;
   make the GHCR packages public or give the cluster a GHCR pull secret
   (connected mode). Air‑gap uses `task mirror` instead.
5. **Coder license** — applied post‑deploy (`coder licenses add`); needed for the
   Premium features this demo uses (OIDC group→role sync, AI Gateway). Standard
   licenses **require telemetry**: the chart keeps `CODER_TELEMETRY_ENABLE=true`,
   and Coder needs outbound access to `telemetry.coder.com` (a fully disconnected
   install needs an air‑gapped license — see [`air-gap.md`](air-gap.md#known-gaps)).

## 1. Install the cluster (STS/OIDC — required for IRSA)
See [`install/`](../install/). Summary:
```bash
cp install/install-config.yaml.example install-config.yaml   # fill pull secret + sshKey (NOT committed)
openshift-install create manifests --dir .
ccoctl aws create-all --name <cluster> --region us-east-1 \
  --credentials-requests-dir <crs> --output-dir .            # creates the IAM OIDC provider
openshift-install create cluster --dir .
```

## 2. IRSA roles (after install)
In `terraform/terraform.tfvars` set `oidc_provider_arn` + `oidc_issuer_host`, and
`enable_bedrock = true` for connected‑mode Bedrock. **Leave
`create_route53_zone = true`** — flipping it to `false` destroys the zone created
in step 0 (see [`terraform/`](../terraform/)).
```bash
oc get authentication cluster -o jsonpath='{.spec.serviceAccountIssuer}'   # -> oidc_* in terraform.tfvars
cd terraform && terraform apply                                            # creates cert-manager (+ optional Bedrock) roles
export CERT_MANAGER_ROLE_ARN=$(terraform output -raw cert_manager_role_arn)
# Connected mode with Claude Code / Bedrock (needs enable_bedrock = true):
export CODER_BEDROCK_ROLE_ARN=$(terraform output -raw coder_bedrock_role_arn)
```

## 3. GPU node
`task deploy` runs `task gpu-node` itself, so this step is optional (run it early
only to start the ~5‑10 min node provisioning sooner):
```bash
task gpu-node        # derives a g5.2xlarge GPU MachineSet from a worker MachineSet (idempotent)
```
The `nvidia.com/gpu.present=true` label only appears **after** `task deploy` has
installed NFD + the NVIDIA GPU operator and synced the `gpu` app — don't wait for
it before step 4. The model‑serving app turns Healthy once the label and the GPU
are present.

## 4. Deploy
```bash
task preflight                 # tooling + cluster login + warns on missing IRSA/pull-secret
task deploy                    # connected (default)
# or, air-gap:
task mirror                    # images + OCI model + oc-mirror into the internal/mirror registry
task deploy MODE=airgap
task status                    # Argo apps + InferenceService + routes + GPU node
```
`task deploy` runs: **bootstrap** (operators → Argo root app‑of‑apps) →
**irsa** (annotate cert‑manager SA from `CERT_MANAGER_ROLE_ARN`) → **gpu-node** →
**wait-apps** (Argo Healthy+Synced) → **coder-irsa** (annotate the coder SA from
`CODER_BEDROCK_ROLE_ARN` + restart Coder; skipped when unset) →
**push-templates** (needs `coder login`) → **ai-provider** (AI Gateway providers
+ Coder Agents models, see [`ai-providers/`](../ai-providers/); needs
`coder login` + license) → air‑gap overlay toggle (`MODE`).

### First Coder login (owner)
Password auth is disabled, so the **first user must come from Keycloak**: the
first OIDC sign‑in on an empty deployment becomes the Coder **owner**.
1. `task creds`, then in a browser open
   `https://coder.apps.cluster.<domain>/api/v2/users/oidc/callback` (starts the
   Keycloak flow directly — an empty deployment redirects `/login` to `/setup`,
   which only offers password/GitHub) and sign in as **`demoadm`** (the `admins`
   group → owner once the license enables role sync; signing in first as
   alice/bob would make a non‑admin the owner).
2. Only then `coder login https://coder.apps.cluster.<domain>` (browser token flow),
   `coder licenses add -f <license.jwt>`, `task push-templates`, and
   `task ai-provider`. Coder 2.39 configures AI Gateway providers and Coder
   Agents models only via the API/UI (provider env vars are ignored), and AI
   Gateway is Premium — the license must show as active (`coder licenses list`;
   telemetry stays enabled, since standard licenses are rejected without it).
   Bedrock (Claude Code; Opus/Haiku Agents models) is configured only when
   Coder has its IRSA role (`CODER_BEDROCK_ROLE_ARN` → `task coder-irsa`).

If `coder login` asks *"Would you like to create the first user?"*, answer
**no** — it creates a *password* owner that can never sign in (password auth is
off) and stops the first OIDC user from becoming owner.

### Persona first logins (users are just‑in‑time)
There is no SCIM push from Keycloak. A persona only exists in Coder and Gitea
after its **first SSO login** to each:
- **Coder** — OIDC group→role/group sync runs at login, so log in once as each
  persona (`alice`, `bob`, and `demoadm` again if its first login predated the
  license) to populate groups/roles.
- **Gitea** — accounts auto‑register on first login (username = Keycloak
  `nickname`). Add personas as repo collaborators after that, or pre‑create them
  with `gitea admin user create` in the Gitea pod.

## Credentials
No secret is committed. Persona passwords are generated in‑cluster (ESO) and live
only in `Secret/keycloak-realm-secrets`:
```bash
task creds     # personas (alice/bob/demoadm) + Keycloak admin console, read live
```
Requires cluster‑admin (`kube:admin` at install; `demoadm` once the realm is up).
Machine client secrets are wired automatically and intentionally not printed.
Override the namespace with `task creds KEYCLOAK_NS=<ns>`.

## Reset (between demos)
```bash
task reset
```
What it does: deletes + re‑runs the Keycloak realm import job (hard‑refreshing
the `keycloak` Argo app) and prints hints. What it does **not** do: rotate
credentials (delete `Secret/keycloak-realm-secrets` in the Keycloak namespace
and ESO regenerates it), or delete workspaces/chats (use the Coder UI or
`coder delete`). Infra is untouched. _Not yet validated live._

## Teardown
```bash
DESTROY_CONFIRM=yes INSTALL_DIR=<dir> task destroy   # openshift-install destroy
cd terraform && terraform destroy                    # Route53 zone + IRSA roles
```
Then delete the NS delegation record for `base_domain` from the **parent** zone
(e.g. `coderdemo.io`, often in another AWS account) — Terraform doesn't manage it.

## Acceptance (definition of done — P7)
Fresh account → steps 0–4 → SSO‑gated Coder, a `workspace-basic` from the
workspace image, a `workspace-agent` whose AI CLI answers from the
in‑cluster RHOAI model; `task deploy MODE=airgap` denies workspace egress yet the
agent still answers in‑cluster; `task reset` returns to clean. No hand‑run
scripts; no code↔live drift.

**Status (2026‑11‑10):** connected mode **passed** on a fresh account (OCP 4.21,
2 AZs): 11/11 Argo apps Synced/Healthy, Keycloak SSO for all personas into Coder
and Gitea, both templates, Claude Code + Codex + Coder Agents via AI Gateway
(vLLM and Bedrock). **Pending:** `MODE=airgap` (known gaps in
[`air-gap.md`](air-gap.md#known-gaps)) and `task reset`.
