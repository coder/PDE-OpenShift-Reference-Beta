# manifests/coder

Supporting resources for the Coder Helm release (ADR D1/D5/D6). Synced by the
`coder-config` Argo Application (`gitops/apps/coder-config.yaml`, sync-wave 2)
into the `coder` namespace, before the Coder chart app (`gitops/apps/coder.yaml`,
wave 3).

| File | Purpose |
|------|---------|
| `postgres-cluster.yaml` | CNPG Postgres `coder-db` (auto-generates `coder-db-app` Secret with `uri`). |
| `secrets.yaml` | ESO `coder-oidc-client-secret` (Keycloak `coder` client secret via `keycloak-realm-kv`). |
| `routes.yaml` | OpenShift Routes: `coder` (access URL) + `coder-wildcard` (`*.coder.apps…` workspace apps). The IngressController `wildcardPolicy` they need is set in `manifests/cert-manager/ingresscontroller-default-cert.yaml`. |

Three Secrets back Coder, all generated/shared in-cluster (never in git):
`coder-db-app` (CNPG), `coder-oidc-client-secret` (ESO), and `coder-gitea-oauth`
(written by the SCM phase's registration Job for Coder's external Git auth).

Login is Keycloak-only (D1). Group→role sync and AI Gateway are Premium/Phase-4
items; a Coder license is supplied at deploy time (never committed, D5).
