# terraform/
Cluster prerequisites and (connected-mode only) IRSA roles — e.g. cert-manager→Route53,
Coder→Bedrock. Copy `terraform.tfvars.example` → `terraform.tfvars` (gitignored) and set
`base_domain`/account. No secret values in git (D5); `terraform.tfvars` and
`terraform/.cluster/` are gitignored.
