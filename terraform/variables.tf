# Terraform inputs — copy terraform.tfvars.example to terraform.tfvars (gitignored).
# No secrets here (D5): the Red Hat pull secret + Coder license are deploy-time
# env, and the OIDC provider is read from the installed cluster.

variable "aws_region" {
  type        = string
  description = "AWS region for the cluster + DNS."
  default     = "us-east-1"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI/SSO profile for the target account (empty = default chain)."
  default     = ""
}

variable "base_domain" {
  type        = string
  description = "Public base domain; cluster installs under <cluster_name>.<base_domain>."
  default     = "rh-pde.coderdemo.io"
}

variable "cluster_name" {
  type        = string
  description = "OpenShift cluster name (-> apps.<cluster_name>.<base_domain>)."
  default     = "cluster"
}

variable "create_route53_zone" {
  type        = bool
  description = "Create the Route53 public hosted zone for base_domain. If the zone already exists (delegated), set false and the config reads it as a data source."
  default     = true
}

# From the INSTALLED cluster (STS/OIDC): the IAM OIDC provider ARN and issuer
# host. Get after `openshift-install`:
#   oc get authentication cluster -o jsonpath='{.spec.serviceAccountIssuer}'
# -> e.g. https://<bucket>.s3.<region>.amazonaws.com/<infra-id>  (issuer host)
# and the matching IAM OIDC provider ARN in the account.
variable "oidc_provider_arn" {
  type        = string
  description = "IAM OIDC provider ARN of the installed cluster (for IRSA trust). Empty disables IRSA role creation."
  default     = ""
}

variable "oidc_issuer_host" {
  type        = string
  description = "OIDC issuer host (no scheme) used in the IRSA trust 'sub' condition, e.g. <bucket>.s3.<region>.amazonaws.com/<infra-id>."
  default     = ""
}

variable "enable_bedrock" {
  type        = bool
  description = "Create the Coder->Bedrock IRSA role (connected-mode AI only)."
  default     = false
}
