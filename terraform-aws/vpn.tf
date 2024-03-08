# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Data                                             ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
data "aws_subnets" "vpn_network" {
  for_each = var.aws.resources.vpn
  filter {
    name   = "vpc-id"
    values = [module.vpc[each.value.vpc].vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = [for key in each.value.subnets : join(",", ["${local.translation_regions[var.aws.region]}-${var.aws.profile}-vpc-${each.value.vpc}-${key}"])]
  }
}

# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Module                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝

# ╔═════════════════════════════╗
# ║ Create VPN CA               ║
# ╚═════════════════════════════╝
resource "tls_private_key" "vpn_ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "vpn_ca" {
  private_key_pem       = tls_private_key.vpn_ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 87600 # 10 years
  subject {
    common_name  = "${local.translation_regions[var.aws.region]}-${var.aws.profile}.vpn"
    organization = "ACME"
  }
  allowed_uses = [
    "key_encipherment",
    "cert_signing",
    "server_auth",
    "client_auth",
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

# resource "local_file" "vpn_ca" {
#   content  = tls_self_signed_cert.vpn_ca.cert_pem
#   filename = "${path.root}/data/${terraform.workspace}/certs/CA.${local.translation_regions[var.aws.region]}.vpn_ca-${var.aws.profile}.vpn.cert"
# }

# ╔═════════════════════════════╗
# ║ Create VPN Server Certs     ║
# ╚═════════════════════════════╝

resource "tls_private_key" "vpn_server" {
  for_each  = var.aws.resources.vpn
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "vpn_server" {
  depends_on      = [tls_private_key.vpn_server]
  for_each        = var.aws.resources.vpn
  private_key_pem = tls_private_key.vpn_server[each.key].private_key_pem
  dns_names       = ["${each.key}.${local.translation_regions[var.aws.region]}-${var.aws.profile}.vpn"]
  subject {
    common_name  = "${each.key}.${local.translation_regions[var.aws.region]}-${var.aws.profile}.vpn"
    organization = "Indra Transportes"
    country      = "ES"
  }
}

resource "tls_locally_signed_cert" "vpn_server" {
  depends_on = [tls_cert_request.vpn_server, tls_private_key.vpn_ca, tls_self_signed_cert.vpn_ca]
  for_each   = var.aws.resources.vpn

  cert_request_pem      = tls_cert_request.vpn_server[each.key].cert_request_pem
  ca_private_key_pem    = tls_private_key.vpn_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.vpn_ca.cert_pem
  validity_period_hours = 8760
  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
    "client_auth",
  ]
}

resource "aws_acm_certificate" "vpn_server" {
  for_each          = var.aws.resources.vpn
  private_key       = tls_private_key.vpn_server[each.key].private_key_pem
  certificate_body  = tls_locally_signed_cert.vpn_server[each.key].cert_pem
  certificate_chain = tls_self_signed_cert.vpn_ca.cert_pem
}

# resource "local_file" "vpn_server_key" {
#   for_each = var.aws.resources.vpn
#   content  = tls_private_key.vpn_server[each.key].private_key_pem
#   filename = "${path.root}/data/${terraform.workspace}/certs/${each.key}.${local.translation_regions[var.aws.region]}.vpn_ca-${var.aws.profile}.vpn.key"
# }

# resource "local_file" "vpn_server_crt" {
#   for_each = var.aws.resources.vpn
#   content  = tls_locally_signed_cert.vpn_server[each.key].cert_pem
#   filename = "${path.root}/data/${terraform.workspace}/certs/${each.key}.${local.translation_regions[var.aws.region]}.vpn_ca-${var.aws.profile}.vpn.crt"
# }

# resource "local_file" "vpn_server_csr" {
#   for_each = var.aws.resources.vpn
#   content  = tls_cert_request.vpn_server[each.key].cert_request_pem
#   filename = "${path.root}/data/${terraform.workspace}/certs/${each.key}.${local.translation_regions[var.aws.region]}.vpn_ca-${var.aws.profile}.vpn.csr"
# }

# ╔═════════════════════════════╗
# ║ Create VPN Client Certs     ║
# ╚═════════════════════════════╝


resource "tls_private_key" "vpn_client" {
  for_each  = { for k, v in var.aws.resources.vpn : k => v if v.type == "certificate" }
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "vpn_client" {
  depends_on      = [tls_private_key.vpn_client]
  for_each        = { for k, v in var.aws.resources.vpn : k => v if v.type == "certificate" }
  private_key_pem = tls_private_key.vpn_client[each.key].private_key_pem
  dns_names       = ["${each.key}-client.${local.translation_regions[var.aws.region]}-${var.aws.profile}.vpn"]

  subject {
    common_name  = "${each.key}-client.${local.translation_regions[var.aws.region]}-${var.aws.profile}.vpn"
    organization = "Indra Transportes"
    country      = "ES"
  }
}

resource "tls_locally_signed_cert" "vpn_client" {
  depends_on            = [tls_cert_request.vpn_client, tls_private_key.vpn_ca, tls_self_signed_cert.vpn_ca]
  for_each              = { for k, v in var.aws.resources.vpn : k => v if v.type == "certificate" }
  cert_request_pem      = tls_cert_request.vpn_client[each.key].cert_request_pem
  ca_private_key_pem    = tls_private_key.vpn_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.vpn_ca.cert_pem
  validity_period_hours = 8760
  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
    "client_auth",
  ]
}

resource "aws_acm_certificate" "vpn_client" {
  for_each          = { for k, v in var.aws.resources.vpn : k => v if v.type == "certificate" }
  private_key       = tls_private_key.vpn_client[each.key].private_key_pem
  certificate_body  = tls_locally_signed_cert.vpn_client[each.key].cert_pem
  certificate_chain = tls_self_signed_cert.vpn_ca.cert_pem
}

# resource "local_file" "vpn_client_key" {
#   for_each = { for k, v in var.aws.resources.vpn : k => v if v.type == "certificate" }
#   content  = tls_private_key.vpn_client[each.key].private_key_pem
#   filename = "${path.root}/data/${terraform.workspace}/certs/${each.key}-client.${local.translation_regions[var.aws.region]}.vpn_ca-${var.aws.profile}.vpn.key"
# }

# resource "local_file" "vpn_client_crt" {
#   for_each = { for k, v in var.aws.resources.vpn : k => v if v.type == "certificate" }
#   content  = tls_locally_signed_cert.vpn_client[each.key].cert_pem
#   filename = "${path.root}/data/${terraform.workspace}/certs/${each.key}-client.${local.translation_regions[var.aws.region]}.vpn_ca-${var.aws.profile}.vpn.crt"
# }

# resource "local_file" "vpn_client_csr" {
#   for_each = { for k, v in var.aws.resources.vpn : k => v if v.type == "certificate" }
#   content  = tls_cert_request.vpn_client[each.key].cert_request_pem
#   filename = "${path.root}/data/${terraform.workspace}/certs/${each.key}-client.${local.translation_regions[var.aws.region]}.vpn_ca-${var.aws.profile}.vpn.csr"
# }

# ╔═════════════════════════════╗
# ║ Create IAM SAML Provider    ║
# ╚═════════════════════════════╝

resource "aws_iam_saml_provider" "vpn" {
  for_each               = { for k, v in var.aws.resources.vpn : k => v if v.type == "federated" }
  name                   = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-vpn-${each.key}"
  saml_metadata_document = each.value.saml_file
  tags                   = merge(local.common_tags, each.value.tags)
}

# ╔═════════════════════════════╗
# ║ Extend Security Group Rules ║
# ╚═════════════════════════════╝

module "vpn_sg_ingress" {
  source            = "terraform-aws-modules/security-group/aws"
  version           = "5.1.0"
  for_each          = var.aws.resources.vpn
  create_sg         = false
  security_group_id = module.sg[each.value.sg].security_group_id
  ingress_with_cidr_blocks = [
    {
      from_port   = each.value.vpn_port
      to_port     = each.value.vpn_port
      protocol    = each.value.transport_protocol != null ? each.value.transport_protocol : each.value.type == "certificate" ? "udp" : "tcp"
      description = "Vpn access from ${each.value.transport_protocol != null ? each.value.transport_protocol : each.value.type == "certificate" ? "udp" : "tcp"} ${each.value.client_cidr_block} port ${each.value.vpn_port}"
      cidr_blocks = each.value.client_cidr_block
    }
  ]
}

# ╔═════════════════════════════╗
# ║ Deploy VPN & assoicate nat  ║
# ╚═════════════════════════════╝

resource "aws_ec2_client_vpn_endpoint" "this" {
  depends_on = [module.vpc, module.sg, module.vpn_sg_ingress]
  for_each   = var.aws.resources.vpn
  tags = merge(
    local.common_tags,
    each.value.tags,
    {
      Name = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-vpn-${each.key}"
    }
  )
  description = "${each.key} - VPN for ${each.value.type} in VPC ${each.value.vpc}"

  server_certificate_arn = aws_acm_certificate.vpn_server[each.key].arn
  client_cidr_block      = each.value.client_cidr_block
  transport_protocol     = each.value.transport_protocol != null ? each.value.transport_protocol : each.value.type == "certificate" ? "udp" : "tcp"
  authentication_options {
    type                       = "${each.value.type}-authentication"
    root_certificate_chain_arn = each.value.type == "certificate" ? aws_acm_certificate.vpn_client[each.key].arn : null
    saml_provider_arn          = each.value.type == "federated" ? aws_iam_saml_provider.vpn[each.key].arn : null
  }
  connection_log_options {
    enabled = false
  }
  security_group_ids    = [module.sg[each.value.sg].security_group_id]
  split_tunnel          = each.value.split_tunnel
  session_timeout_hours = each.value.session_timeout_hours
  vpc_id                = module.vpc[each.value.vpc].vpc_id
  vpn_port              = each.value.vpn_port
}

resource "aws_ec2_client_vpn_network_association" "this" {
  for_each               = var.aws.resources.vpn
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this[each.key].id
  subnet_id              = element(data.aws_subnets.vpn_network[each.key].ids, 0)
}

resource "aws_ec2_client_vpn_authorization_rule" "this" {
  for_each               = var.aws.resources.vpn
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this[each.key].id
  target_network_cidr    = each.value.target_network_cidr
  authorize_all_groups   = true
}

# ╔═════════════════════════════╗
# ║ Create OVPN Files           ║
# ╚═════════════════════════════╝

resource "local_file" "ovpn_config_certificate" {
  for_each = { for k, v in var.aws.resources.vpn : k => v if v.type == "certificate" }
  filename = "data/${terraform.workspace}/vpn/${each.key}/vpn.${local.translation_regions[var.aws.region]}-${var.aws.profile}.${each.key}.ovpn"
  content = templatefile("${path.module}/templates/ovpn-certificate.tftpl", {
    vpn_server    = replace(aws_ec2_client_vpn_endpoint.this[each.key].dns_name, "^\\*\\.", "")
    vpn_port      = each.value.vpn_port
    vpn_transport = each.value.transport_protocol != null ? each.value.transport_protocol : "udp"
    keystore_cert = tls_self_signed_cert.vpn_ca.cert_pem
    cert_pem      = tls_locally_signed_cert.vpn_client[each.key].cert_pem
    cert_key      = tls_private_key.vpn_client[each.key].private_key_pem
    cert_name     = "${each.key}.${local.translation_regions[var.aws.region]}-${var.aws.profile}.vpn"
  })
}

resource "local_file" "ovpn_config_federeated" {
  for_each = { for k, v in var.aws.resources.vpn : k => v if v.type == "federated" }
  filename = "data/${terraform.workspace}/vpn/${each.key}/vpn.${local.translation_regions[var.aws.region]}-${var.aws.profile}.${each.key}.ovpn"
  content = templatefile("${path.module}/templates/ovpn-federated.tftpl", {
    vpn_server    = aws_ec2_client_vpn_endpoint.this[each.key].dns_name
    vpn_port      = each.value.vpn_port
    vpn_transport = each.value.transport_protocol != null ? each.value.transport_protocol : "tcp"
    keystore_cert = tls_self_signed_cert.vpn_ca.cert_pem
    cert_name     = "${each.key}.${local.translation_regions[var.aws.region]}-${var.aws.profile}.vpn"
  })
}