# workspace-basic

A plain browser-dev Coder workspace on OpenShift (ADR D7): **code-server**
(VS Code in the browser, run from the copy pre-baked into the image — offline
start), optional **Git clone** from the in-cluster Gitea, and **dotfiles**.
No AI tooling (use [`workspace-agent`](../workspace-agent/) for that).

- Runs as a `restricted-v2` pod from `ubi9-node-workspace` (registry per `MODE`:
  GHCR in connected mode, the internal registry in air-gap; see [`../README.md`](../README.md#images)).
- Persistent `/home/coder` PVC (size chosen at create, immutable after).
- Params: CPU, memory, disk size, optional Git repo.
- Gitea repos authenticate automatically via Coder external auth (`gitea`).

```bash
task push-templates      # or: coder templates push workspace-basic -d ./templates/workspace-basic --variable image_registry=<registry>
```
