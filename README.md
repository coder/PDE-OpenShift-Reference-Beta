# PDE‑OpenShift‑Reference (Beta)

**Coder Partner/Field Deployed Engineering — OpenShift reference architecture & demo.**

A minimal, repeatable GitOps deployment of **Coder Workspaces + Coder Agents on
Red Hat OpenShift**, that also demonstrates an **air‑gapped reference architecture
on OpenShift + OpenShift AI (RHOAI)**. The same manifests run in two modes:

| | **Connected** (easy) | **Air‑gap‑ready** (reference arch) |
|---|---|---|
| Images | ghcr + internal registry | **internal registry only** (oc‑mirror) |
| Model serving | RHOAI (in‑cluster) **+** optional AWS Bedrock | **RHOAI only** (in‑cluster vLLM) |
| Identity | Keycloak (RHBK) | Keycloak (RHBK), in‑cluster |
| SCM | in‑cluster Git (**Gitea**) | in‑cluster Git (**Gitea**) |
| Workspace egress | allowed | **default‑deny** (NetworkPolicy / Agent Firewall) |
| Secrets | generated in‑cluster / provided at deploy — **never in git** | same |

> **Status: model serving landed (Phases 0–4).** GitOps bootstrap + operators
> (P1), Keycloak/RHBK identity (P2a), Gitea in‑cluster SCM (P2b), Coder (P3), and
> **RHOAI model serving** (P4) — KServe RawDeployment + vLLM ServingRuntime +
> Qwen2.5‑7B InferenceService on A10G, wired to Coder's AI Gateway — are in
> `main`. Upcoming: workspace templates (P5), air‑gap mode (P6), fresh‑cluster
> acceptance (P7). Locked decisions: [`docs/decisions.md`](docs/decisions.md).

## Design in one screen
- **Single IdP** — Keycloak/RHBK only. (D1)
- **In‑cluster Git** — no external SCM VM. (D2)
- **OpenShift AI (RHOAI)** KServe + vLLM ServingRuntime; default model
  **Qwen2.5‑7B‑Instruct on 1× A10G `g5.2xlarge`** (Llama‑70B/L40S documented as a
  scale‑up). (D3/D4)
- **No secrets in this public repo — ever.** Values are generated in‑cluster (ESO
  `Password` generators + operator‑managed) or provided at deploy time; the repo
  holds only references/specs. (D5 — see [`docs/decisions.md`](docs/decisions.md))
- **Coder Agents demoed in‑product**; two workspace templates with offline AI CLIs;
  minimal observability. (D6–D8)

## Quickstart (once built)
This repo uses [go-task](https://taskfile.dev) (`task`) as its task runner — install it via https://taskfile.dev/installation/.
```bash
task help          # list targets
task deploy        # one-command deploy (connected mode)  [Phase 7]
task deploy MODE=airgap
task creds         # print demo logins (personas + Keycloak admin), read live from the cluster
task reset         # return to a clean demo state
task destroy
```
`task creds` works as soon as the identity layer is deployed; see
[`docs/deploy.md`](docs/deploy.md#credentials-retrieving-the-generated-demo-logins).

## Repository layout
```
docs/        architecture.md · deploy.md · air-gap.md · decisions.md  (5 docs max)
terraform/   cluster prereqs + (optional) connected-mode IRSA
gitops/      bootstrap/root-app.yaml · operators/ · apps/   (Argo app-of-apps)
manifests/   k8s resources per app (+ air-gap overlays)
templates/   workspace-basic · workspace-agent  (offline AI CLIs)
images/      workspace image builds + internal-registry mirror helper
```

## Read next
- [`docs/architecture.md`](docs/architecture.md) — components + the two run‑modes.
- [`docs/deploy.md`](docs/deploy.md) — deploy/reset runbook.
- [`docs/air-gap.md`](docs/air-gap.md) — disconnected install, mirroring, egress‑deny.
- [`docs/decisions.md`](docs/decisions.md) — the ratified ADRs (D1–D9).

_Lineage: distilled from the RH Summit 2026 demo build, keeping only the proven
pieces (Invent & Simplify)._
