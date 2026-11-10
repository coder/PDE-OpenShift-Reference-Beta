# manifests/gpu

GPU enablement for the RHOAI model server (ADR D3/D4). Synced by the `gpu` Argo
Application (`gitops/apps/gpu.yaml`, sync-wave 1, before `model-serving`). The
NFD + NVIDIA GPU operator Subscriptions are bootstrap-applied from
`gitops/operators/50-node-feature-discovery.yaml` / `60-nvidia-gpu.yaml`; on
their own they do nothing until these CRs exist.

| File | Purpose |
|------|---------|
| `nfd-instance.yaml` | `NodeFeatureDiscovery` — PCI vendor labels (`feature.node.kubernetes.io/pci-10de.present` on NVIDIA nodes). |
| `cluster-policy.yaml` | NVIDIA `ClusterPolicy` (operator default) — driver via Driver Toolkit, device plugin, GFD; labels the node `nvidia.com/gpu.present=true` and exposes `nvidia.com/gpu`. |

The GPU node itself is a MachineSet (`task gpu-node`, g5.2xlarge, tainted
`nvidia.com/gpu=true:NoSchedule`); the operator daemonsets tolerate that taint.
