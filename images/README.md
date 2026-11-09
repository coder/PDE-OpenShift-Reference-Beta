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

Templates pull `…/coder-workspaces/ubi9-node-workspace:latest` (the
`image_registry` default). No secrets in these images; nothing is fetched from
the public internet at workspace start (code-server is baked).
