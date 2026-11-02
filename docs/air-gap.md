# Air‑gapped reference architecture

> Scaffold — this is the disconnected/sovereign story. We ship **simulated‑on‑connected
> first** (fast/cheap: egress‑deny + internal‑registry‑only on a connected cluster),
> with the fully‑disconnected path documented here. Fills in across Phase 6.

## What "air‑gap‑ready" means here
Everything the demo touches is **in‑cluster**; workspace egress is **default‑deny**:
- **Images:** internal OpenShift registry only (no ghcr/docker.io at runtime).
- **Model:** RHOAI (in‑cluster vLLM) only — no Bedrock/public LLM.
- **Identity + SCM:** Keycloak + in‑cluster Git.
- **Secrets:** generated in‑cluster (ESO generators) — no external store dependency (D5).
- **TLS:** cert‑manager with an internal CA (no public ACME).

## Simulated mode (default first)
- Workspace `NetworkPolicy` / Agent Firewall = **default‑deny egress** (allow only
  in‑cluster services: Coder, Git, RHOAI, Keycloak).
- Templates pull only from `image-registry.openshift-image-registry.svc`.
- AI Gateway sovereign provider → in‑cluster RHOAI `InferenceService`.
- Prove it: start a `workspace-agent`, confirm the agent completes a task with egress
  blocked (model answers from in‑cluster).

## Fully disconnected (documented path)
1. **Mirror** images with `oc-mirror` (operators + workload + workspace images) into a
   registry reachable by the cluster. (`make mirror` / `images/` helper.)
2. **ImageDigestMirrorSet / ImageContentSourcePolicy** so pulls resolve to the mirror.
3. **Disconnected OpenShift install** (imageContentSources in `install-config`).
4. **RHOAI** model artifacts mirrored to internal object storage / OCI; `InferenceService`
   references the mirrored model (no HF pulls at runtime).
5. **Coder air‑gapped bundle** + license (provided at deploy; never committed).
6. **cert‑manager** internal CA issuer (no public ACME).

## Carry‑over
`images/` includes the internal‑registry **mirror helper** ported from the prior build
(`mirror-to-internal-registry.sh`) — the seed of the `make mirror` flow.
