# manifests/airgap

The air-gap overlay (ADR, P6) — applied **only** in air-gap mode. Its Argo
Application lives at `gitops/airgap/airgap-app.yaml` (deliberately **outside**
`gitops/apps/`, which the root app-of-apps recurses), so connected deploys never
sync it. Toggle with `task deploy MODE=airgap` / `task airgap-disable`.

| File | Purpose |
|------|---------|
| `workspace-egress-netpol.yaml` | NetworkPolicy: **default-deny egress** in `coder-workspaces`; allows only DNS + in-cluster (router, Coder, `rhoai-serving`, Gitea, internal registry). |
| `image-digest-mirror-set.yaml` | `ImageDigestMirrorSet` redirecting external image sources → the internal/disconnected mirror. |

## The sovereignty proof
With the egress policy applied, a workspace cannot reach the public internet,
yet the AI agent still answers: its traffic goes to the in-cluster Coder AI
Gateway → RHOAI vLLM (Qwen2.5-7B), all cluster-internal.

## Model weights offline
Air-gap can't use `hf://` at serve time. `task mirror` builds/pushes an OCI
**ModelCar** (`mirror/modelcar/`) and `task airgap-enable` patches the
InferenceService `storageUri` to `oci://…` (the `model-serving` Argo app
`ignoreDifferences` that field so it isn't reverted).

**Not yet validated live.** Before using this overlay, tune the egress
allow‑list and replace the IDMS with the one oc‑mirror generates for your mirror
host. See the known gaps in [`docs/air-gap.md`](../../docs/air-gap.md#known-gaps)
(the AI CLIs are fetched at workspace start, Bedrock, license/telemetry).
