# Architecture decisions (ADRs)

Concise, current decisions for this reference architecture. One entry per decision:
what we picked, why, and the alternative we rejected. (Distilled from the RH Summit
2026 build — we keep the conclusions, not the 900‑line saga.)

> Status key: ✅ ratified 2026‑11‑02.

## D1 — Single IdP: Keycloak (RHBK) only ✅
**Picked:** Keycloak/RHBK as the one identity provider for Coder (and, in‑cluster,
for Git + Grafana). **Why:** drops dual‑IdP + group‑sync complexity; GitHub OAuth
isn't reachable air‑gapped. **Rejected:** dual‑IdP (Keycloak + GitHub).

## D2 — In‑cluster Git (Gitea or GitLab via operator) ✅
**Picked:** SCM runs **in the cluster**. **Why:** the prior EC2‑Omnibus GitLab caused
a cloud‑init systemd deadlock, a private‑subnet + edge‑Route cutover, and an SSM‑PAT
dance — none of it air‑gap‑able or repeatable. **Rejected:** GitLab‑on‑EC2.
**Open:** Gitea (lightest) vs GitLab‑operator (closer to prior narrative) — decide in P2.

## D3 — Model serving via OpenShift AI (RHOAI) ✅
**Picked:** RHOAI **KServe + vLLM ServingRuntime** (`ServingRuntime` + `InferenceService`).
**Why:** RHOAI *is* the Red Hat sovereign‑AI story; replaces 6 hand‑rolled vLLM
Deployments and their drift. **Rejected:** hand‑rolled vLLM Deployments/MachineSet zoo.

## D4 — Default model: Qwen2.5‑7B‑Instruct on 1× A10G `g5.2xlarge` ✅
**Picked:** the model/GPU we actually validated — `Qwen/Qwen2.5‑7B‑Instruct`, 16K ctx,
TP‑1, `--tool-call-parser hermes`, on a single A10G. **Why:** cost‑effective default;
proven to tool‑call correctly. Llama‑3.3‑70B INT4 (TP‑2, L40S/`g6e`) is documented as
a **scale‑up** (kept at 0 for cost). **Rejected:** Llama‑70B/L40S as the default.

## D5 — No secret VALUES in the repo (it is public) — ever ✅
**Picked:** the repo contains only secret *references + generator specs*. Values come
from three places, none of them git:
1. **Operator/platform‑generated** in‑cluster — CNPG DB creds, Keycloak initial admin,
   cert‑manager TLS.
2. **Deploy‑time random‑generated in‑cluster** via **External Secrets Operator
   `Password` generators** — persona passwords + OIDC client secrets. The Keycloak
   realm **render Job** injects them into the realm; each consumer reads the *same*
   generated Secret. (OIDC client‑secret coordination with zero values in git.)
3. **Deploy‑time‑provided** — Red Hat pull secret, Coder license — via `make`/env,
   never committed. Bedrock (connected mode) uses **IRSA**, no static key.

**Why:** a public reference repo must contain *zero* secret material — not even
encrypted. **Rejected:** **Sealed Secrets / SOPS** — they still commit *ciphertext*
to permanent public history (and sealed values are useless to anyone cloning the
repo). In **connected** mode ESO may optionally be backed by AWS Secrets Manager —
still only references in git; in **air‑gap** mode ESO generators (or an in‑cluster
Vault) keep it dependency‑free. A `gitleaks` CI gate enforces "no secrets in git."

## D6 — Coder Agents demoed in‑product ✅
**Picked:** the headline flow is Coder Agents (Tasks/chat) in the Coder UI. The
GitLab‑issue→workspace **bridge** is optional / a later phase. **Why:** removes a
bespoke Go service from the critical path.

## D7 — Two workspace templates ✅
**Picked:** `workspace-basic` and `workspace-agent` (offline AI CLIs baked into the
image). An **egress‑controlled** flavor is folded into air‑gap mode rather than a
separate template. **Rejected:** the prior 5 templates + firewall/no‑firewall split.

## D8 — Minimal observability ✅
**Picked:** OpenShift user‑workload monitoring + 1–2 dashboards. **Rejected:** the
`coder-observability` Helm umbrella (optional add‑on later).

## D9 — Five docs max ✅
**Picked:** `README.md` + `docs/{architecture,deploy,air-gap,decisions}.md`. Anything
else gets folded in or dropped. **Why:** the prior repo drifted to 33 markdown files.

---

### Logistics (locked 2026‑11‑02)
- Repo: `greg-the-coder/PDE-OpenShift-Reference-Beta` (public fork).
- AWS sandbox **342934376218**, us‑east‑1. New DNS drops `rhsummit`:
  `base_domain = rh-pde.coderdemo.io` → apps at `*.apps.cluster.rh-pde.coderdemo.io`
  (confirm exact base domain before cluster provisioning).
- Air‑gap: **simulated‑on‑connected first**; fully‑disconnected path documented.
- Cloud LLM: **Bedrock kept as an optional connected‑mode provider**; air‑gap = RHOAI only.
