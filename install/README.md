# install

Cluster bring-up inputs for the fresh-account acceptance run (P7). These are
**examples / templates** — the cluster is created by `openshift-install`, not by
this repo; `task deploy` takes over once the cluster (and a GPU node) exist.

| File | Purpose |
|------|---------|
| `install-config.yaml.example` | OpenShift IPI on AWS, **STS/OIDC (`credentialsMode: Manual`)** so IRSA works. Copy → fill pull secret + sshKey (deploy-time, never committed). |
| `gpu-machineset.yaml.example` | g5.2xlarge (A10G) GPU worker MachineSet. Prefer `task gpu-node` to derive it from a live worker MachineSet. |

## Order of operations (fresh account)
1. **Quotas/DNS:** request G-instance vCPU quota; create + delegate the Route53 zone (`terraform apply -target=aws_route53_zone.base`).
2. **Install (STS):** `openshift-install create manifests` → `ccoctl aws create-all` → `openshift-install create cluster`.
3. **IRSA:** capture the cluster OIDC and `terraform apply` (roles) — see `terraform/`.
4. **GPU node (optional here):** `task gpu-node` (or apply the example MachineSet). `task deploy` also runs it. The `nvidia.com/gpu.present` label only appears after `task deploy` installs NFD and the NVIDIA operator, so don't wait for it.
5. **Deploy:** `task deploy` (connected) or `task deploy MODE=airgap` (after `task mirror`).

See [`docs/deploy.md`](../docs/deploy.md) for the full runbook incl. prerequisites.
