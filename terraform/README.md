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
#  -> set oidc_provider_arn + oidc_issuer_host (and create_route53_zone=false) in tfvars
terraform apply
terraform output cert_manager_role_arn           # -> export CERT_MANAGER_ROLE_ARN for `task deploy`
```

No secrets are stored here (D5). The cluster must be installed in **STS/OIDC
mode** (Manual credentials mode + `ccoctl`) for IRSA to work — see `install/`.
