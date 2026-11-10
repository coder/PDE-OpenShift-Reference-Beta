# templates

Coder workspace templates for OpenShift (ADR D7). Two templates, both running
as `restricted-v2` pods from the pre-baked `ubi9-node-workspace` image
(`images/`), cloning from the in-cluster Gitea via Coder external auth.

| Template | Purpose |
|----------|---------|
| [`workspace-basic`](workspace-basic/) | Browser dev: code-server (offline) + optional Gitea clone + dotfiles. No AI. |
| [`workspace-agent`](workspace-agent/) | `basic` + offline **Claude Code** & **Codex** routed through the Coder **AI Gateway** (OpenAI provider → in-cluster vLLM Qwen; Bedrock/Anthropic = connected mode). |

## Push a template
```bash
coder templates push workspace-basic -d ./templates/workspace-basic
coder templates push workspace-agent -d ./templates/workspace-agent
```
Registry modules (`registry.coder.com/...`) are fetched at push time; for
air-gap they are vendored/mirrored in Phase 6.

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

**Validated:** `terraform validate` (coder + kubernetes providers). Live
workspace create + AI round-trip to the in-cluster model is a P7 item.
