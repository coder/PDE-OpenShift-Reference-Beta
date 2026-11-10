# templates

Coder workspace templates for OpenShift (ADR D7). Two templates, both running
as `restricted-v2` pods from the `ubi9-node-workspace` image (`images/`,
code-server pre-baked), cloning from the in-cluster Gitea via Coder external auth.

| Template | Purpose |
|----------|---------|
| [`workspace-basic`](workspace-basic/) | Browser dev: code-server (pre-baked, offline start) + optional Gitea clone + dotfiles. No AI. |
| [`workspace-agent`](workspace-agent/) | `basic` + **Claude Code** & **Codex** (installed by pinned registry modules at workspace start) routed through the Coder **AI Gateway** (provider `openai` → in-cluster vLLM Qwen; provider `bedrock` = connected mode). |

## Push a template
```bash
task push-templates      # both templates; sets image_registry (per MODE) + anthropic_model
```
Prefer this over a bare `coder templates push`: a push reuses the previous
version's variable values, so stale values would carry over. Registry modules
(`registry.coder.com/...`) are fetched at push time; for air-gap, pre-fetch
them with `task vendor-modules`. The agent template's provider and module pins
are listed in [`workspace-agent/`](workspace-agent/#pins-verified-live-2026-11-10).

## Images
The `image_registry` variable picks where workspaces pull `ubi9-node-workspace:latest`.
`task push-templates` sets it per `MODE`:
- **connected** (default): `ghcr.io/coder/pde-openshift-reference` (public GHCR
  build from `.github/workflows/build-images.yml`).
- **airgap**: the OpenShift internal registry (the template default), filled by
  `task mirror` / `NS=coder-workspaces ./images/mirror-to-internal-registry.sh`.

Override with `task push-templates WORKSPACE_IMAGE_REGISTRY=<registry/path>`.
Workspaces run in the `coder-workspaces` namespace (created by `coder-config`;
the Coder chart's `workspaceNamespaces` grants its ServiceAccount pod/PVC rights there).

**Validated:** `terraform validate`, plus a live run (2026-11-10, connected):
both templates build workspaces, and Codex → vLLM Qwen and Claude Code →
Bedrock both complete round-trips through the AI Gateway.
