# images

UBI9-based Coder workspace images for OpenShift (ADR D7) + the internal-registry
mirror helper. Source-of-truth images are built to GHCR by
`.github/workflows/build-images.yml`, then mirrored into the OpenShift internal
registry for a self-contained / air-gapped pull path.

| Path | Purpose |
|------|---------|
| `ubi9-base-workspace/` | UBI 9.7 + dev tooling, zsh/tmux/neovim, starship, OCP uid_entrypoint (restricted-v2 random-UID support). |
| `ubi9-node-workspace/` | `FROM` base + Node 22 (yarn/pnpm) + **code-server pre-baked** (offline start); Copilot unlinked from VS Code core. The image the templates use. |
| `mirror-to-internal-registry.sh` | Copy both images from GHCR into `image-registry.openshift-image-registry.svc:5000/coder-workspaces`. |

```bash
# after GHCR build:
NS=coder-workspaces ./images/mirror-to-internal-registry.sh
```

Templates pull `<image_registry>/ubi9-node-workspace:latest`. `task push-templates`
sets the registry: GHCR in connected mode, this internal registry in air-gap.
The images hold no secrets. code-server is baked in, so `workspace-basic` fetches
nothing at start. `workspace-agent` is different: its registry modules
**download Claude Code and Codex at every workspace start**, because they aren't
in the image (see [`docs/air-gap.md`](../docs/air-gap.md#known-gaps)).
