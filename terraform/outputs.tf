output "route53_zone_id" {
  description = "Hosted zone id for base_domain."
  value       = local.zone_id
}

output "route53_name_servers" {
  description = "NS records to delegate base_domain from the parent zone (only when this config creates the zone)."
  value       = var.create_route53_zone ? aws_route53_zone.base[0].name_servers : null
}

output "cert_manager_role_arn" {
  description = "Annotate the cert-manager SA with this (task deploy reads CERT_MANAGER_ROLE_ARN)."
  value       = local.irsa_enabled ? aws_iam_role.cert_manager[0].arn : null
}

output "coder_bedrock_role_arn" {
  description = "Annotate the coder SA with this for connected-mode Bedrock."
  value       = local.irsa_enabled && var.enable_bedrock ? aws_iam_role.coder_bedrock[0].arn : null
}
