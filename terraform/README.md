# terraform

Fresh-account prerequisites that are **not** the OpenShift cluster itself
(the cluster is created by `openshift-install` — see [`install/`](../install/)).

| File | Purpose |
|------|---------|
| `versions.tf` | Terraform + AWS provider pins. |
| `variables.tf` | Inputs (region, base_domain, cluster_name, OIDC provider, flags). |
| `main.tf` | Route53 public zone (+ NS for delegation) and **IRSA IAM roles** — cert-manager→Route53 (ACME dns01) and optional Coder→Bedrock. |
| `outputs.tf` | Zone id/nameservers + the role ARNs consumed by `task deploy`. |

## Two-phase apply (IRSA needs the installed cluster's OIDC)
```bash
cp terraform.tfvars.example terraform.tfvars    # edit; gitignored (D5)

# Phase 1 — before install: create the DNS zone, then delegate its NS from the
# parent coderdemo.io zone.
terraform init
terraform apply -target=aws_route53_zone.base
terraform output route53_name_servers           # add these NS to the parent zone

# Phase 2 — after `openshift-install`: capture the cluster OIDC and create IRSA.
oc get authentication cluster -o jsonpath='{.spec.serviceAccountIssuer}'
#  -> set oidc_provider_arn + oidc_issuer_host (+ enable_bedrock=true for
#     connected-mode Bedrock) in tfvars. KEEP create_route53_zone=true.
terraform apply
terraform output cert_manager_role_arn           # -> export CERT_MANAGER_ROLE_ARN for `task deploy`
terraform output coder_bedrock_role_arn          # -> export CODER_BEDROCK_ROLE_ARN (task coder-irsa / ai-provider)
```

> **Do not flip `create_route53_zone` to `false` on a zone this config
> created.** That removes `aws_route53_zone.base` from config and the next
> `apply` **destroys the zone** (and every record the cluster installer and
> cert-manager wrote into it). `false` is only for a zone that was created
> *outside* this Terraform state.

## Teardown
`terraform destroy` deletes the zone and IAM roles. The NS delegation record in
the **parent** zone (e.g. `coderdemo.io`, often a different AWS account) is not
managed here — delete it manually.

No secrets are stored here (D5). The cluster must be installed in **STS/OIDC
mode** (Manual credentials mode + `ccoctl`) for IRSA to work — see `install/`.
