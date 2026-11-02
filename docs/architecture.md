# Architecture

> Scaffold — the diagrams and full component detail land in Phase 8. This captures
> the shape and the two run‑modes so the build has a target.

## Components (minimal set)

| Layer | Component | Notes |
|---|---|---|
| Platform | OpenShift 4.x IPI on AWS | 3× converged control/worker + 1× GPU node (`g5.2xlarge`, A10G) |
| GitOps | Red Hat OpenShift GitOps (Argo CD) | app‑of‑apps from `gitops/apps/` |
| Operators | cert‑manager, **OpenShift AI (RHOAI)**, External Secrets, CNPG | installed at bootstrap (`gitops/operators/`) |
| Identity | Keycloak (RHBK) — realm `demo` | single IdP (D1) |
| SCM | in‑cluster Git — **Gitea** (Helm) | (D2) SSO login via Keycloak; also Coder's external Git‑auth provider |
| Coder | Helm via GitOps | OIDC → Keycloak; AI Gateway (`CODER_AI_GATEWAY_*`) |
| Model serving | RHOAI KServe + vLLM `ServingRuntime` | Qwen2.5‑7B on A10G (D3/D4) |
| Agents | Coder Agents (chatd) in‑product | sovereign (RHOAI) + optional Bedrock |
| Workspaces | `workspace-basic`, `workspace-agent` | offline AI CLIs; internal‑registry images |
| Observability | OCP user‑workload monitoring (+1–2 dashboards) | minimal (D8) |
| Secrets | in‑cluster generation (ESO generators) / operator‑managed | **none in git** (D5) |

## Two run‑modes (same manifests, one toggle)

| Capability | Connected | Air‑gap‑ready |
|---|---|---|
| Images | ghcr + internal registry | internal registry only (oc‑mirror) |
| Model | RHOAI + optional Bedrock (IRSA) | RHOAI only |
| Workspace egress | allowed | default‑deny (NetworkPolicy / Agent Firewall) |
| TLS | cert‑manager + ACME | cert‑manager internal CA |
| Secrets backend | ESO generators (optionally AWS SM) | ESO generators (or in‑cluster Vault) |

## Request flow (demo loop)
`user → Coder (SSO via Keycloak) → create workspace (internal‑registry image) →
Coder Agents chat → AI Gateway → {RHOAI in‑cluster | Bedrock (connected)} →
agent edits code in the workspace → push to in‑cluster Git`.

_Diagrams: `docs/images/` (generated in Phase 8 — connected + air‑gap views)._

## Gitea OAuth relationships (D2)

Two distinct, independent OAuth/OIDC links:
- **Gitea → Keycloak** (user login): Gitea runs an OIDC login source against the
  `demo` realm (`gitea` client); users auto‑provision on first SSO login.
- **Coder → Gitea** (workspace Git auth): Coder is registered as an OAuth2 app
  *inside* Gitea so workspaces obtain Gitea tokens via Coder external auth
  (`CODER_EXTERNAL_AUTH_0_*`, type `gitea`). The client id/secret are generated
  by Gitea and stored in the in‑cluster Secret `coder/coder-gitea-oauth`
  (wired by Coder in Phase 3). Neither secret is committed (D5).
