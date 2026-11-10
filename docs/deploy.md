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
   Premium features this demo uses (OIDC group→role sync, AI Gateway).

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
```bash
oc get authentication cluster -o jsonpath='{.spec.serviceAccountIssuer}'   # -> oidc_* in terraform.tfvars
cd terraform && terraform apply                                            # creates cert-manager (+ optional Bedrock) roles
export CERT_MANAGER_ROLE_ARN=$(terraform output -raw cert_manager_role_arn)
# Connected mode with Claude Code / Bedrock (needs enable_bedrock = true):
export CODER_BEDROCK_ROLE_ARN=$(terraform output -raw coder_bedrock_role_arn)
```

## 3. GPU node
```bash
task gpu-node        # derives a g5.2xlarge GPU MachineSet from a worker MachineSet
```
Wait for the node to join and the NVIDIA GPU operator to label it
`nvidia.com/gpu.present=true`.

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
task reset     # re-seed the demo realm; drop demo workspaces via Coder UI/CLI; infra untouched
```

## Teardown
```bash
DESTROY_CONFIRM=yes INSTALL_DIR=<dir> task destroy   # openshift-install destroy
cd terraform && terraform destroy                    # Route53 zone + IRSA roles
```

## Acceptance (definition of done — P7)
Fresh account → steps 0–4 → SSO‑gated Coder, a `workspace-basic` from the
internal‑registry image, a `workspace-agent` whose AI CLI answers from the
in‑cluster RHOAI model; `task deploy MODE=airgap` denies workspace egress yet the
agent still answers in‑cluster; `task reset` returns to clean. No hand‑run
scripts; no code↔live drift.
