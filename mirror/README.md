# mirror

Air-gap mirroring inputs (P6). Driven by `task mirror`.

| Path | Purpose |
|------|---------|
| `imageset-config.yaml` | oc-mirror `ImageSetConfiguration` — the 8 operators (redhat + certified catalogs) + workload images (Coder, Gitea, vLLM, UBI9 workspaces, ose-cli). |
| `modelcar/Dockerfile` | OCI **ModelCar** packaging the Qwen2.5-7B weights under `/models` so KServe can serve from the internal registry (`oci://…`) with no serve-time egress. |

## Run
```bash
task mirror      # 1) workspace images GHCR->internal  2) build+push modelcar  3) oc-mirror operators+images
```
- oc-mirror and podman/docker are provided at deploy time (not committed).
- The ModelCar build needs Hugging Face connectivity **at build time only**;
  thereafter the cluster pulls the model from the internal/disconnected registry.
- oc-mirror emits the authoritative `ImageDigestMirrorSet`/`CatalogSource` to
  apply to the cluster; `manifests/airgap/image-digest-mirror-set.yaml` is the
  illustrative committed target.

**P7:** pin the catalog index tag to the cluster OCP minor and the vLLM image
digest to the installed RHOAI (`vllm-cuda-runtime-template`); run the real
mirror + disconnected pull-through.
