# install

Cluster bring-up inputs for the fresh-account acceptance run (P7). These are
**examples / templates** — the cluster is created by `openshift-install`, not by
this repo; `task deploy` takes over once the cluster (and a GPU node) exist.

| File | Purpose |
|------|---------|
| `install-tools.sh` | Installs the CLIs into `~/.local/bin` (`oc`, `openshift-install`, `ccoctl`, `oc-mirror` pinned to `OCP_VERSION`, plus AWS CLI, go-task, and Terraform/`jq` if missing). Idempotent; Linux x86_64. |
| `render-install-config.sh` | Renders `install-config.yaml` from the example plus a pull secret and SSH public key read from files, into a directory **outside** the repo (mode 0600, plus a `.bak`). |
| `install-config.yaml.example` | OpenShift IPI on AWS, **STS/OIDC (`credentialsMode: Manual`)** so IRSA works; 2 AZs (EIP quota). Matches the accepted live run; never commit a filled copy. |
| `gpu-machineset.yaml.example` | g5.2xlarge (A10G) GPU worker MachineSet. Prefer `task gpu-node` to derive it from a live worker MachineSet. |

## Order of operations (fresh account)
0. **Tools:** `./install/install-tools.sh`.
1. **Quotas/DNS:** request G-instance vCPU quota; create + delegate the Route53 zone (`terraform apply -target=aws_route53_zone.base`).
2. **Install (STS):** `./install/render-install-config.sh …` → `oc adm release extract --credentials-requests` → `ccoctl aws create-all` → `openshift-install create manifests` (+ copy ccoctl output) → `openshift-install create cluster`.
3. **IRSA:** capture the cluster OIDC and `terraform apply` (roles) — see `terraform/`.
4. **GPU node (optional here):** `task gpu-node` (or apply the example MachineSet). `task deploy` also runs it. The `nvidia.com/gpu.present` label only appears after `task deploy` installs NFD and the NVIDIA operator, so don't wait for it.
5. **Deploy:** `task deploy` (connected) or `task deploy MODE=airgap` (after `task mirror`).

See [`docs/deploy.md`](../docs/deploy.md) for the full runbook incl. prerequisites,
and [`docs/working-implementation-guide.md`](../docs/working-implementation-guide.md)
for the exact commands used on the live run.
