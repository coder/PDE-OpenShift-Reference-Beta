# Air‑gapped reference architecture

This is the disconnected/sovereign story. We ship **simulated‑on‑connected first**
(egress‑deny + internal‑registry‑only + in‑cluster model on a connected cluster),
with the fully‑disconnected path documented below. The overlay is implemented,
but **`MODE=airgap` has not yet been validated live** — the connected acceptance
run (2026‑11‑10) passed; read [Known gaps](#known-gaps) before demoing air‑gap.

## What "air‑gap‑ready" means here
Everything the demo touches is **in‑cluster**; workspace egress is **default‑deny**:
- **Images:** internal OpenShift registry only (redirected via `ImageDigestMirrorSet`).
- **Model:** RHOAI (in‑cluster vLLM) only — no Bedrock/public LLM; weights served
  from an OCI **ModelCar** in the internal registry (no `hf://` at serve time).
- **Identity + SCM:** Keycloak + in‑cluster Gitea.
- **Secrets:** generated in‑cluster (ESO generators) — no external store (D5).
- **TLS:** cert‑manager. NOTE: the committed issuer is public ACME (Route53 dns01);
  a fully‑disconnected install needs a cert‑manager **internal CA** issuer
  (not implemented yet — no public ACME reachable).

## Toggle
Same manifests, one switch:
```bash
task deploy MODE=airgap     # applies the air-gap overlay (gitops/airgap app)
task airgap-disable         # back to connected posture
```
The overlay (`manifests/airgap/`, synced by `gitops/airgap/airgap-app.yaml` —
kept out of `gitops/apps/` so connected never applies it) adds:
- `workspace-egress-netpol.yaml` — **default‑deny egress** in `coder-workspaces`;
  allows only DNS + in‑cluster (router, Coder, `rhoai-serving`, Gitea, registry).
- `image-digest-mirror-set.yaml` — redirects external image sources to the mirror.
- plus `task airgap-enable` patches the InferenceService `storageUri` → `oci://`
  (the OCI ModelCar); the `model-serving` app `ignoreDifferences` that field.

## Prove it
Start a `workspace-agent`, confirm the AI agent completes a task with workspace
egress blocked — the model answers from the in‑cluster RHOAI vLLM via the Coder
AI Gateway (all cluster‑internal).

## Mirror (populate the registry)
```bash
task mirror     # 1) workspace images GHCR->internal  2) build+push Qwen OCI ModelCar  3) oc-mirror operators+images
```
Inputs in `mirror/`: `imageset-config.yaml` (oc-mirror: 8 operators + workload
images) and `modelcar/Dockerfile` (Qwen2.5‑7B weights). oc-mirror + podman/docker
are provided at deploy time, never committed.

## Fully disconnected (documented path)
1. **Mirror** with `task mirror` into a registry reachable by the cluster.
2. Apply the oc‑mirror‑generated **`ImageDigestMirrorSet`/`CatalogSource`** (the
   committed `manifests/airgap/image-digest-mirror-set.yaml` is the illustrative target).
3. **Disconnected OpenShift install** (`imageContentSources` in `install-config`).
4. **Model:** served from the OCI ModelCar in the internal registry (no HF pulls).
5. **Coder:** air‑gapped image via GHCR→mirror; license provided at deploy (never committed).
6. **Templates:** pre‑fetch Coder registry modules (`task vendor-modules`) so
   `coder templates push` needs no external module fetch.
7. **cert‑manager:** internal CA `ClusterIssuer` (replaces public ACME) — not in
   the repo yet.

## Known gaps
Found during the connected acceptance run; none are fixed yet.
1. **AI CLIs are downloaded at workspace start.** `workspace-agent` installs
   Claude Code and Codex through the Coder registry modules when the workspace
   starts. They aren't in the image, so under the egress‑deny NetworkPolicy the
   install fails. Air‑gap needs the CLIs baked into `ubi9-node-workspace` (or
   served from an in‑cluster mirror) with the modules' install steps disabled.
   `task vendor-modules` caches module *source* only, not the CLI binaries.
2. **Bedrock stays configured.** `task ai-provider` enables the `bedrock`
   provider whenever the `coder` SA carries the IRSA annotation, and the overlay
   only restricts **workspace** egress (Coder server egress is untouched). For a
   true RHOAI‑only posture, run air‑gap without `CODER_BEDROCK_ROLE_ARN`
   (remove the SA annotation, re‑run `task ai-provider`) and switch the
   `workspace-agent` `anthropic_model` / Agents default to the Qwen model.
   Claude Code's default model is Bedrock Haiku.
3. **Coder license + telemetry.** Standard licenses require telemetry
   (`CODER_TELEMETRY_ENABLE=true`) and outbound access from the Coder server. A
   fully disconnected install needs an **air‑gapped Coder license**.
4. **IDMS is illustrative.** `manifests/airgap/image-digest-mirror-set.yaml`
   must be replaced by the oc‑mirror‑generated IDMS/CatalogSource for the real
   mirror host.
5. **No internal‑CA issuer** (see TLS above).
6. **`task airgap-enable` patches the model `storageUri` to `oci://`
   unconditionally.** Run `task mirror` first, or the predictor can't pull the
   ModelCar.

## Carry‑over
`images/mirror-to-internal-registry.sh` (ported from the prior build) is step 1
of `task mirror`.
