# Fresh-account prerequisites that are NOT the OpenShift cluster itself
# (the cluster is created by `openshift-install`, see install/). This covers:
#   1. The Route53 public hosted zone for base_domain (+ its NS for delegation).
#   2. IRSA IAM roles the in-cluster controllers assume (no static keys, D5):
#        - cert-manager -> Route53 (ACME dns01 for the wildcard cert)
#        - (optional) Coder -> Bedrock (connected-mode AI)
#
# IRSA roles trust the INSTALLED cluster's OIDC provider, so apply in two phases:
#   phase 1 (before install): terraform apply -target=aws_route53_zone.base  (if creating the zone)
#   phase 2 (after install, with oidc_* set): terraform apply
# Set create_route53_zone=false + oidc_* vars once the cluster exists.

# ---- 1. DNS ------------------------------------------------------------------
resource "aws_route53_zone" "base" {
  count = var.create_route53_zone ? 1 : 0
  name  = var.base_domain
  comment = "pde-openshift-reference base domain (delegate NS from parent zone)"
}

data "aws_route53_zone" "base" {
  count        = var.create_route53_zone ? 0 : 1
  name         = var.base_domain
  private_zone = false
}

locals {
  zone_id = var.create_route53_zone ? aws_route53_zone.base[0].zone_id : data.aws_route53_zone.base[0].zone_id
  # IRSA roles are only created once the cluster OIDC provider is known.
  irsa_enabled = var.oidc_provider_arn != "" && var.oidc_issuer_host != ""
}

# ---- 2a. cert-manager -> Route53 (IRSA) --------------------------------------
data "aws_iam_policy_document" "cert_manager_trust" {
  count = local.irsa_enabled ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:cert-manager:cert-manager"]
    }
  }
}

data "aws_iam_policy_document" "cert_manager_route53" {
  count = local.irsa_enabled ? 1 : 0
  statement {
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${local.zone_id}"]
  }
  statement {
    effect    = "Allow"
    actions   = ["route53:ListHostedZonesByName"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "cert_manager" {
  count              = local.irsa_enabled ? 1 : 0
  name               = "${var.cluster_name}-cert-manager-route53"
  assume_role_policy = data.aws_iam_policy_document.cert_manager_trust[0].json
}

resource "aws_iam_role_policy" "cert_manager" {
  count  = local.irsa_enabled ? 1 : 0
  name   = "route53-dns01"
  role   = aws_iam_role.cert_manager[0].id
  policy = data.aws_iam_policy_document.cert_manager_route53[0].json
}

# ---- 2b. Coder -> Bedrock (IRSA, optional, connected mode) -------------------
data "aws_iam_policy_document" "coder_bedrock_trust" {
  count = local.irsa_enabled && var.enable_bedrock ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:coder:coder"]
    }
  }
}

resource "aws_iam_role" "coder_bedrock" {
  count              = local.irsa_enabled && var.enable_bedrock ? 1 : 0
  name               = "${var.cluster_name}-coder-bedrock"
  assume_role_policy = data.aws_iam_policy_document.coder_bedrock_trust[0].json
}

resource "aws_iam_role_policy" "coder_bedrock" {
  count = local.irsa_enabled && var.enable_bedrock ? 1 : 0
  name  = "bedrock-invoke"
  role  = aws_iam_role.coder_bedrock[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:Converse", "bedrock:ConverseStream"]
      Resource = "*"
    }]
  })
}
