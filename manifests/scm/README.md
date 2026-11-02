# manifests/scm

In-cluster Git — **Gitea** (ADR D2). Supporting resources for the Gitea Helm
release; synced by the `scm-config` Argo Application
(`gitops/apps/scm-config.yaml`, sync-wave 1) into the `scm` namespace. The Gitea
chart itself is the separate `scm` Application (`gitops/apps/scm.yaml`, wave 2).

| File | Purpose |
|------|---------|
| `postgres-cluster.yaml` | CNPG Postgres `gitea-db` (auto-generates `gitea-db-app` Secret). |
| `route.yaml` | OpenShift Route (edge TLS) for `gitea.apps.cluster.rh-pde.coderdemo.io` → Service `gitea-http`. |
| `secrets.yaml` | ESO: generated admin Secret `gitea-admin`; `gitea-oidc` (Keycloak `gitea` client secret from `keycloak-realm-kv`), shaped for the chart's `existingSecret`. |
| `coder-oauth-job.yaml` | Idempotent PostSync Job registering Coder as an OAuth2 app in Gitea → writes `coder-gitea-oauth` Secret in the `coder` namespace (consumed by Phase 3 Coder). |

Two OAuth relationships live here:
- **Gitea → Keycloak** (SSO login): chart `gitea.oauth` OIDC source against the
  `demo` realm; auto-registers users (`ENABLE_AUTO_REGISTRATION`).
- **Coder → Gitea** (workspace Git auth): the registration Job above; Phase 3
  wires Coder's `CODER_EXTERNAL_AUTH_0_*` (type `gitea`) to it.

No secret value is committed; all credentials are generated/shared in-cluster
(ADR D5).
