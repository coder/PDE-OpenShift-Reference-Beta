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
| `workspaces-namespace.yaml` | `coder-workspaces` namespace for workspace pods/PVCs (the chart's `workspaceNamespaces` RBAC targets it; `Prune=false`). |

Three Secrets back Coder, all generated/shared in-cluster (never in git):
`coder-db-app` (CNPG), `coder-oidc-client-secret` (ESO), and `coder-gitea-oauth`
(written by the SCM phase's registration Job for Coder's external Git auth).

Login is Keycloak-only (D1), with OIDC group→role/group sync applied **at each
login** (no SCIM, so a persona's groups appear after its first login). A Premium
Coder license is supplied at deploy time (`coder licenses add`, never committed,
D5). It requires telemetry, which the chart keeps on (`CODER_TELEMETRY_ENABLE=true`).
AI Gateway providers (`openai` → vLLM, `bedrock` → IRSA) and the Coder Agents
models are configured through the API by `task ai-provider` (Coder 2.39 ignores
provider env vars). See [`ai-providers/`](../../ai-providers/).
