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
| SCM | in‑cluster Git (Gitea / GitLab‑operator) | (D2) |
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
