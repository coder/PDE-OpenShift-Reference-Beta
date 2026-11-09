# workspace-basic

A plain browser-dev Coder workspace on OpenShift (ADR D7): **code-server**
(VS Code in the browser, run from the copy pre-baked into the image — offline
start), optional **Git clone** from the in-cluster Gitea, and **dotfiles**.
No AI tooling (use [`workspace-agent`](../workspace-agent/) for that).

- Runs as a `restricted-v2` pod from `ubi9-node-workspace` (internal registry).
- Persistent `/home/coder` PVC (size chosen at create, immutable after).
- Params: CPU, memory, disk size, optional Git repo.
- Gitea repos authenticate automatically via Coder external auth (`gitea`).

```bash
coder templates push workspace-basic -d ./templates/workspace-basic
```
