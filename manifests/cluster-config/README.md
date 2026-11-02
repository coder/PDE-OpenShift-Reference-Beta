# manifests/cluster-config

Cluster-scoped configuration synced by the `cluster-config` Argo Application
(`gitops/apps/cluster-config.yaml`).

| File | Purpose |
|------|---------|
| `oauth-cluster.yaml` | Cluster `OAuth` CR — single Keycloak OIDC IdP (`demo` realm), `groups` claim mapping. |
| `keycloak-oidc-externalsecret.yaml` | `ExternalSecret` in `openshift-config` materializing the shared `openshift` client secret as `keycloak-openshift-oidc-secret` (via `ClusterSecretStore keycloak-realm-kv`). |
| `cluster-admin-binding.yaml` | Binds the Keycloak `admins` group to `cluster-admin`. |
