# gitops/apps/
Argo CD `Application`s (app-of-apps, synced by `gitops/bootstrap/root-app.yaml`).
All in AppProject `default`. 11 apps, by sync-wave:

| Wave | App | Source |
|---|---|---|
| -2 | `cluster-config` (incl. **committed Argo RBAC**) | `manifests/cluster-config` |
| -1 | `external-secrets` | `manifests/external-secrets` |
| 0 | `cert-manager` (issuers + apps wildcard cert) | `manifests/cert-manager` |
| 1 | `keycloak` (RHBK + realm `demo`) | `manifests/keycloak` |
| 1 | `gpu` (NFD instance + NVIDIA ClusterPolicy) | `manifests/gpu` |
| 1 | `scm-config` (Gitea DB + secrets) | `manifests/scm` |
| 2 | `scm` (Gitea) | Helm chart `gitea` (dl.gitea.com/charts) |
| 2 | `coder-config` (Coder DB + secrets + workspace namespace) | `manifests/coder` |
| 2 | `model-serving` (RHOAI vLLM Qwen2.5-7B) | `manifests/model-serving` |
| 3 | `coder` | Helm chart `coder` 2.39.0 (helm.coder.com/v2) |
| 3 | `observability` (placeholder, nothing deployed yet; D8) | `manifests/observability` |

Templates aren't an Argo app: `task push-templates` pushes them to Coder. The
air-gap overlay app (`gitops/airgap/`) sits outside this directory, so connected
deploys never sync it.
