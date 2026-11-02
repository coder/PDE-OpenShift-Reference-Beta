# manifests/external-secrets

External Secrets Operator (ESO) controller instance (ADR D5). The
Subscription/OperatorGroup are bootstrap-applied from
`gitops/operators/30-external-secrets.yaml`; this directory deploys the
controller itself.

| File | Purpose |
|------|---------|
| `externalsecretsconfig.yaml` | `ExternalSecretsConfig/cluster` — deploys the external-secrets controller into the `external-secrets` namespace. |

No external provider (e.g. AWS Secrets Manager) is wired: all demo secrets are
generated in-cluster by ESO `Password` generators (see
`manifests/keycloak/realm-secrets.yaml`) and shared via a Kubernetes-provider
`ClusterSecretStore`. Nothing secret is committed to this public repo.
