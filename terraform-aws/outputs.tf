# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Locals                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
locals {

  eks_config_yaml = fileexists("data/${terraform.workspace}/eks/main/admin.kubeconfig") ? yamldecode(file("data/${terraform.workspace}/eks/main/admin.kubeconfig")) : null

  eks_config = {
    host                   = local.eks_config_yaml != null ? local.eks_config_yaml.clusters[0].cluster.server : lookup(var.aws.resources, "eks", null) == null ? "" : lookup(var.aws.resources.eks, "main", null) == null ? "" : module.eks["main"].cluster_endpoint
    cluster_ca_certificate = local.eks_config_yaml != null ? base64decode(local.eks_config_yaml.clusters[0].cluster["certificate-authority-data"]) : lookup(var.aws.resources, "eks", null) == null ? "" : lookup(var.aws.resources.eks, "main", null) == null ? "" : base64decode(module.eks["main"].cluster_certificate_authority_data)
    exec_api_version       = "client.authentication.k8s.io/v1beta1"
    exec_command           = "aws"
    args                   = local.eks_config_yaml != null ? local.eks_config_yaml.users[0].user.exec.args : ["eks", "get-token", "--cluster-name", lookup(var.aws.resources, "eks", null) == null ? "" : lookup(var.aws.resources.eks, "main", null) == null ? "" : module.eks["main"].cluster_name, "--region", var.aws.region, "--profile", var.aws.profile]
  }

  output_eks_config = {
    host                   = local.eks_config.host != null ? local.eks_config.host : lookup(var.aws.resources, "eks", null) == null ? "" : lookup(var.aws.resources.eks, "main", null) == null ? "" : module.eks["main"].cluster_endpoint
    cluster_ca_certificate = local.eks_config.cluster_ca_certificate != null ? local.eks_config.cluster_ca_certificate : lookup(var.aws.resources, "eks", null) == null ? "" : lookup(var.aws.resources.eks, "main", null) == null ? "" : base64decode(module.eks["main"].cluster_certificate_authority_data)
    api_version            = local.eks_config.exec_api_version != null ? local.eks_config.exec_api_version : "client.authentication.k8s.io/v1beta1"
    command                = local.eks_config.exec_command != null ? local.eks_config.exec_command : "aws"
    args                   = local.eks_config.args != null ? local.eks_config.args : ["eks", "get-token", "--cluster-name", lookup(var.aws.resources, "eks", null) == null ? "" : lookup(var.aws.resources.eks, "main", null) == null ? "" : module.eks["main"].cluster_name, "--region", var.aws.region, "--profile", var.aws.profile]
  }


  output_eks_nodegroups = length(module.eks) == 0 ? {} : {
    for key, value in module.eks :
    key =>
    "╠ Node groups: \n\t║ ${join("\n\t║", [
      for nodeg in value.eks_managed_node_groups :
      " \t→ ${nodeg.node_group_id}"
    ])}"
  }

  output_elc_memcache_endpoints = length(aws_elasticache_cluster.this) == 0 ? {} : {
    for key, value in aws_elasticache_cluster.this :
    key =>
    "╠ Nodes:\n\t║\t→ ${join("\n\t║\t→", [
      for node in value.cache_nodes :
      "${node.id} -- ${node.address}:${node.port}"
    ])}"
  }
  output_elc_redis_endpoints = length(aws_elasticache_replication_group.this) == 0 ? {} : {
    for key, value in aws_elasticache_replication_group.this :
    key => lookup(value, "primary_endpoint_address", null) == null ? join("\n\t", [
      "╠ Configuration endpoints: ${value.configuration_endpoint_address}",
      "╠ Number cluster cache: ${value.num_cache_clusters}",
      "╠ Number node groups: ${value.num_node_groups}"]) : join("\n\t", [
      "╠ Endpoints:",
      "║\t→ Primary: ${value.primary_endpoint_address}:${value.port}",
      "║\t→ Reader: ${value.reader_endpoint_address}:${value.port}"
    ])
  }

  output_cloudfront_origin = length(aws_cloudfront_distribution.this) == 0 ? {} : {
    for key, value in aws_cloudfront_distribution.this :
    key =>
    "╠ Cloudfront origin \n\t║\t║ ${join("\n\t║\t→", [
      for origin in value.origin :
      "Domain Name: ${origin.domain_name}\n\t║\t╚ Id: ${origin.origin_id} "
    ])}"
  }

  output_cloudfront_policy = length(aws_cloudfront_cache_policy.this) == 0 ? {} : {
    for key, value in aws_cloudfront_cache_policy.this :
    key =>
    "╚ Cloudfront Custom Cache Policies \n\t\t║ ${join("\n\t\t║", [
      for policy in aws_cloudfront_cache_policy.this :
      " Id: ${policy.id}\n\t\t╚ Name: ${policy.name}"
    ])}"
  }

  # output_eks_cluster_addons = length(module.eks) == 0 ? {} : {
  #   for key, value in module.eks :
  #   key =>
  #   "╠ Cluster Addons \n\t║ ${join("\n\t║", [
  #   for addon in value.cluster_addons :
  #   " \t→ ${addon.addon_name}"
  #   ])}"
  # }

  output_iam_role = length(aws_iam_role.this) == 0 ? {} : {
    for key, value in aws_iam_role.this :
    key => "${join("\n\t", [
      "\t(${key})${value.name}:",
      "\t╚ Assume role policy: ${value.assume_role_policy}"
    ])}"
  }

  output_iam_policy = length(aws_iam_policy.this) == 0 ? {} : {
    for key, value in aws_iam_policy.this :
    key => "${join("\n\t", [
      "\t(${key})${value.name}:",
      "\t╠  Path: ${value.path}",
      "\t╚ Policy id: ${value.policy_id}",
    ])}"
  }

  output_iam_role_policy_attachment = length(aws_iam_role_policy_attachment.this) == 0 ? {} : {
    for key, value in aws_iam_role_policy_attachment.this :
    key => "${join("\n\t", [
      "\t(${key})${value.id}:",
      "\t╠  Policy arn: ${value.policy_arn}",
      "\t╚ Role: ${value.role}",
    ])}"
  }

  output_iam_instance_profile = length(aws_iam_instance_profile.this) == 0 ? {} : {
    for key, value in aws_iam_instance_profile.this :
    key => "${join("\n\t", [
      "\t(${key})${value.id}:",
      "\t╠ Path: ${value.path}",
      "\t╚ Role: ${value.role}",
    ])}"
  }

  output = {
    # Let AWS the first output
    a_aws = templatefile("${path.module}/templates/output-aws.tftpl",
      {
        profile     = var.aws.profile,
        region      = var.aws.region,
        environment = lookup(local.translation_environments, element(split("-", var.aws.profile), 1), null) == null ? "custom" : local.translation_environments[element(split("-", var.aws.profile), 1)],
        owner       = var.aws.owner
    })

    a_vpc = length(module.vpc) == 0 ? "" : templatefile("${path.module}/templates/output-vpc.tftpl",
      {
        resource_map = module.vpc
    })

    alb = length(module.alb) == 0 ? "" : templatefile("${path.module}/templates/output-alb.tftpl",
      {
        resource_map = module.alb
    })

    asg = length(module.asg) == 0 ? "" : templatefile("${path.module}/templates/output-asg.tftpl",
      {
        resource_map = module.asg
    })

    cloudfront = length(aws_cloudfront_distribution.this) == 0 ? "" : templatefile("${path.module}/templates/output-cloudfront.tftpl",
      {
        resource_map    = aws_cloudfront_distribution.this,
        resource_origin = local.output_cloudfront_origin,
        resource_policy = local.output_cloudfront_policy
    })

    ec2 = length(module.ec2) == 0 ? "" : templatefile("${path.module}/templates/output-ec2.tftpl",
      {
        resource_map = module.ec2
    })

    eks = length(module.eks) == 0 ? "" : templatefile("${path.module}/templates/output-eks.tftpl",
      {
        resource_map        = module.eks,
        resource_node_group = local.output_eks_nodegroups
    })

    elc_memcache = length(aws_elasticache_cluster.this) == 0 ? "" : templatefile("${path.module}/templates/output-elc_memcache.tftpl",
      {
        resource_map       = aws_elasticache_cluster.this,
        resource_endpoints = local.output_elc_memcache_endpoints
    })

    elc_redis = length(aws_elasticache_replication_group.this) == 0 ? "" : templatefile("${path.module}/templates/output-elc_redis.tftpl",
      {
        resource_map       = aws_elasticache_replication_group.this,
        resource_endpoints = local.output_elc_redis_endpoints
    })

    iam = length(aws_iam_role.this) != 0 || length(aws_iam_policy.this) != 0 || length(aws_iam_role_policy_attachment.this) != 0 || length(aws_iam_instance_profile.this) != 0 ? templatefile("${path.module}/templates/output-iam.tftpl",
      {
        resource_map_iam_role                   = aws_iam_role.this
        resource_map_iam_policy                 = aws_iam_policy.this
        resource_map_iam_role_policy_attachment = aws_iam_role_policy_attachment.this
        resource_map_iam_instance_profile       = aws_iam_instance_profile.this
        resource_iam_role                       = local.output_iam_role != {} ? local.output_iam_role : null,
        resource_iam_policy                     = local.output_iam_policy != {} ? local.output_iam_policy : null
        resource_iam_role_policy_attachment     = local.output_iam_role_policy_attachment != {} ? local.output_iam_role_policy_attachment : null,
        resource_iam_instance_profile           = local.output_iam_instance_profile != {} ? local.output_iam_instance_profile : null
    }) : ""

    kinesis = length(aws_kinesis_video_stream.this) == 0 ? "" : templatefile("${path.module}/templates/output-kinesis.tftpl",
      {
        resource_map = aws_kinesis_video_stream.this
    })

    mq = length(aws_mq_broker.this) == 0 ? "" : templatefile("${path.module}/templates/output-mq.tftpl",
      {
        resource_map    = aws_mq_broker.this,
        resource_config = var.aws.resources.mq,
        password        = random_password.mq
    })

    nlb = length(module.nlb) == 0 ? "" : templatefile("${path.module}/templates/output-nlb.tftpl",
      {
        resource_map = module.nlb
    })

    rds = length(module.rds) == 0 ? "" : templatefile("${path.module}/templates/output-rds.tftpl",
      {
        resource_map    = module.rds,
        resource_config = var.aws.resources.rds,
        password        = random_password.rds
    })

    s3 = length(module.s3) == 0 ? "" : templatefile("${path.module}/templates/output-s3.tftpl",
      {
        resource_map = module.s3
    })

    waf = length(aws_wafv2_web_acl.this) == 0 ? "" : templatefile("${path.module}/templates/output-waf.tftpl",
      {
        resource_map = aws_wafv2_web_acl.this
    })
  }

  merge_ouput = join("", [for key, value in local.output : (value)])
}


# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                            Outputs                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
output "output" {
  value = local.merge_ouput
  # value = flatten([ for sg in var.aws.resources.alternat.sgs : module.sg[sg].security_group_id ])
  # value = local.alternat_vpc_az_maps
}


output "extras" {
  value = ""
  # value = "${jsonencode(aws_mq_broker.this["main"])}"
  # value = local.eks_map_role_binding
  # value = "${jsonencode(module.vpc["main"])}"
  # value = "${jsonencode(module.sg_ingress_rules)}"
}

output "eks_config" {
  value = local.output_eks_config
}