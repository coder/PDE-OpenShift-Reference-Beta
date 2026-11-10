# manifests/keycloak

Red Hat Build of Keycloak (RHBK) — the single demo IdP (ADR D1), plus the
secret-free `demo` realm and the in-cluster credential generation (ADR D5).

Synced by the `keycloak` Argo Application (`gitops/apps/keycloak.yaml`) into the
`keycloak` namespace. The RHBK operator Subscription is bootstrap-applied from
`gitops/operators/35-rhbk.yaml`.

| File | Purpose |
|------|---------|
| `postgres-cluster.yaml` | CNPG Postgres `keycloak-db` (auto-generates `keycloak-db-app` Secret). |
| `keycloak.yaml` | Keycloak CR (v26 operator): 1 replica, edge-TLS via Route, proxy-headers. |
| `route.yaml` | OpenShift Route (edge TLS) for `keycloak.apps.cluster.rh-pde.coderdemo.io`. |
| `realm-secrets.yaml` | ESO `Password` generators (×2) → `keycloak-realm-secrets` (8 keys) + Kubernetes-provider `ClusterSecretStore` `keycloak-realm-kv` for cross-namespace sharing. |
| `realm-template-configmap.yaml` | Secret-free `KeycloakRealmImport` template (groups, users alice/bob/demoadm, OIDC clients coder/gitea/openshift/grafana/argocd) with `__PLACEHOLDER__` tokens. |
| `realm-import-job.yaml` | Argo Sync-hook Job: injects generated secrets into the template and applies the realm. |

No secret value is ever committed; all demo credentials are generated at deploy
time. `task reset` only re-runs the realm import. To rotate the credentials,
delete `Secret/keycloak-realm-secrets` so ESO regenerates it, then re-sync.
The `grafana` and `argocd` clients are defined in the realm, but nothing
consumes them yet.
