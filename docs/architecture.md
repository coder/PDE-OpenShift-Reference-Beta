# Architecture

> Component inventory and the two run‑modes, kept in sync with the connected
> acceptance run (2026‑11‑10). Diagrams are still to come.

## Components (minimal set)

| Layer | Component | Notes |
|---|---|---|
| Platform | OpenShift 4.21 IPI on AWS (STS/IRSA) | 3× control‑plane `m6i.xlarge` + 3× worker `m6i.2xlarge` + 1× GPU worker (`g5.2xlarge`, A10G) across 2 AZs |
| GitOps | Red Hat OpenShift GitOps (Argo CD) | app‑of‑apps from `gitops/apps/` (11 apps, sync waves −2…3) |
| Operators | OpenShift GitOps, cert‑manager, **OpenShift AI (RHOAI)**, External Secrets, CNPG, RHBK (Keycloak), NFD, NVIDIA GPU | installed at bootstrap (`gitops/operators/`) |
| Identity | Keycloak (RHBK) — realm `demo` | single IdP (D1). Users/groups reach Coder and Gitea **just‑in‑time at OIDC login** (no SCIM) |
| SCM | in‑cluster Git — **Gitea** (Helm) | (D2) SSO login via Keycloak; also Coder's external Git‑auth provider |
| Coder | Helm via GitOps (chart 2.39.0) | Keycloak‑only OIDC login (D1) + group/role sync; CNPG Postgres; Gitea external Git auth; Premium license (requires telemetry on); AI Gateway providers + Agents models configured by `task ai-provider` |
| Model serving | RHOAI KServe + vLLM `ServingRuntime` | Qwen2.5‑7B on A10G, **RawDeployment** (no mesh/serverless); OpenAI‑compatible, consumed by Coder AI Gateway as provider `openai` (D3/D4) |
| Agents | Coder Agents (chatd) in‑product | models: Claude Opus 4.5 (default) + Haiku 4.5 via Bedrock (IRSA, connected) and Qwen2.5‑7B via RHOAI |
| Workspaces | `workspace-basic`, `workspace-agent` | restricted‑v2 pods, UBI9 image with code‑server pre‑baked; Gitea clone; agent = Claude Code + Codex **installed by registry modules at workspace start**, routed via AI Gateway (D7) |
| Observability | — | **not implemented yet** (D8 planned: OCP user‑workload monitoring + 1–2 dashboards); `manifests/observability/` is a placeholder |
| Secrets | in‑cluster generation (ESO generators) / operator‑managed | **none in git** (D5) |

## Two run‑modes (same manifests, one toggle)

| Capability | Connected | Air‑gap‑ready |
|---|---|---|
| Images | ghcr (workspace images) + Red Hat/upstream registries | internal registry only (oc‑mirror + IDMS) |
| Model | RHOAI + optional Bedrock (IRSA) | RHOAI only |
| Workspace egress | allowed | default‑deny (NetworkPolicy) |
| TLS | cert‑manager + ACME (Let's Encrypt, Route53 dns01) | cert‑manager internal CA — **not implemented yet** |
| Secrets backend | ESO generators (optionally AWS SM) | ESO generators (or in‑cluster Vault) |

## Request flow (demo loop)
`user → Coder (SSO via Keycloak) → create workspace →
Coder Agents chat / Claude Code / Codex → AI Gateway → {RHOAI in‑cluster | Bedrock (connected)} →
agent edits code in the workspace → push to in‑cluster Git`.

_Diagrams: not yet produced (connected + air‑gap views planned for `docs/images/`)._

## Gitea OAuth relationships (D2)

Two distinct, independent OAuth/OIDC links:
- **Gitea → Keycloak** (user login): Gitea runs an OIDC login source against the
  `demo` realm (`gitea` client); users auto‑provision on first SSO login.
- **Coder → Gitea** (workspace Git auth): Coder is registered as an OAuth2 app
  *inside* Gitea so workspaces obtain Gitea tokens via Coder external auth
  (`CODER_EXTERNAL_AUTH_0_*`, type `gitea`). The client id/secret are generated
  by Gitea and stored in the in‑cluster Secret `coder/coder-gitea-oauth`.
  Neither secret is committed (D5).
