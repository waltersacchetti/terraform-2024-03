# ╔═════════════════════════════╗
# ║ Create RDS yaml             ║
# ╚═════════════════════════════╝

locals {
  yaml_rds = var.aws.resources.rds == 0 ? {} : {
    for key, value in var.aws.resources.rds : key => {
      Engine   = value.engine,
      Version  = value.engine_version,
      Endpoint = module.rds[key].db_instance_endpoint,
      Port     = module.rds[key].db_instance_port,
      Database = value.db_name
      Username = module.rds[key].db_instance_username,
      Password = value.password == null || value.password == "" ? random_password.rds[key].result : value.password,
      Databases = value.engine == "postgres" && length(value.databases) > 0 ? [
        for database in concat(value.databases, [key]) : {
          Database = database,
          Username = database,
          Password = random_password.rds_postgres_db["${key}_${database}"].result,
        }
        ] : [
        {
          Database = key,
          Username = key,
          Password = random_password.rds_postgres_db["${key}_${key}"].result,
        }
      ],
    }
  }
}

resource "local_file" "yaml_rds" {
  count    = length(var.aws.resources.rds) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/rds.yaml"
  content  = yamlencode(local.yaml_rds)
}

# ╔════════════════════════════╗
# ║ Create MQ yaml             ║
# ╚════════════════════════════╝

locals {
  yaml_mq = var.aws.resources.mq == 0 ? {} : {
    for key, value in var.aws.resources.mq : key => {
      Engine    = aws_mq_broker.this[key].engine_type,
      Version   = aws_mq_broker.this[key].engine_version,
      Instances = aws_mq_broker.this[key].instances,
      Username  = value.username,
      Password  = value.password == null || value.password == "" ? random_password.mq[key].result : value.password
    }
  }
}

resource "local_file" "yaml_mq" {
  count    = length(var.aws.resources.mq) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/mq.yaml"
  content  = yamlencode(local.yaml_mq)
}

# ╔═════════════════════════════╗
# ║ Create EC2 yaml             ║
# ╚═════════════════════════════╝

locals {
  yaml_ec2 = var.aws.resources.ec2 == 0 ? {} : {
    for key, value in var.aws.resources.ec2 : key => {
      Ami              = module.ec2[key].ami,
      Instance_Type    = value.instance_type,
      Private_Ip       = module.ec2[key].private_ip,
      Pem_Key_Location = local_file.ec2-key[key].filename
    }
  }
}

resource "local_file" "yaml_ec2" {
  count    = length(var.aws.resources.ec2) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/ec2.yaml"
  content  = yamlencode(local.yaml_ec2)
}

# ╔══════════════════════════════════╗
# ║ Create IAM Role yaml             ║
# ╚══════════════════════════════════╝

locals {
  yaml_iam_role = var.aws.resources.iam == 0 ? {} : {
    for key, value in var.aws.resources.iam : key => can(aws_iam_role.this[key]) ? {
      Name               = aws_iam_role.this[key].name,
      Description        = aws_iam_role.this[key].description,
      Assume_Role_Policy = aws_iam_role.this[key].assume_role_policy
    } : null
  }
  yaml_iam_policy = var.aws.resources.iam == 0 ? {} : {
    for key, value in var.aws.resources.iam : key => can(aws_iam_policy.this[key]) ? {
      Name      = aws_iam_policy.this[key].name,
      Path      = aws_iam_policy.this[key].path,
      Policy_Id = aws_iam_policy.this[key].policy_id
    } : null
  }
  yaml_iam_role_policy_attachment = var.aws.resources.iam == 0 ? {} : {
    for key, value in var.aws.resources.iam : key => can(aws_iam_role_policy_attachment.this[key]) ? {
      Id         = aws_iam_role_policy_attachment.this[key].id,
      Policy_arn = aws_iam_role_policy_attachment.this[key].policy_arn,
      Role       = aws_iam_role_policy_attachment.this[key].role
    } : null
  }
  yaml_iam_instance_profile = var.aws.resources.iam == 0 ? {} : {
    for key, value in var.aws.resources.iam : key => can(aws_iam_instance_profile.this[key]) ? {
      Id   = aws_iam_instance_profile.this[key].id,
      Path = aws_iam_instance_profile.this[key].path,
      Role = aws_iam_instance_profile.this[key].role
    } : null
  }
}

resource "local_file" "yaml_iam" {
  count    = length(var.aws.resources.iam) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/iam.yaml"
  content  = yamlencode({ iam_role = local.yaml_iam_role, iam_policy = local.yaml_iam_policy, iam_role_policy_attachment = local.yaml_iam_role_policy_attachment, iam_instance_profile = local.yaml_iam_instance_profile })
}

# ╔════════════════════════════╗
# ║ Create S3 yaml             ║
# ╚════════════════════════════╝

locals {
  yaml_s3 = var.aws.resources.s3 == 0 ? {} : {
    for key, value in var.aws.resources.s3 : key => {
      Id          = module.s3[key].s3_bucket_id,
      Region      = module.s3[key].s3_bucket_region,
      Domain_Name = module.s3[key].s3_bucket_bucket_domain_name,
      Policy      = module.s3[key].s3_bucket_policy,
    }
  }
}

resource "local_file" "yaml_s3" {
  count    = length(var.aws.resources.s3) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/s3.yaml"
  content  = yamlencode(local.yaml_s3)
}


# ╔════════════════════════════╗
# ║ Create ASG yaml            ║
# ╚════════════════════════════╝

locals {
  yaml_asg = var.aws.resources.asg == 0 ? {} : {
    for key, value in var.aws.resources.asg : key => {
      Name                      = module.asg[key].autoscaling_group_name,
      Ami                       = value.image_id,
      Instance_Type             = value.instance_type,
      Desired_Size              = module.asg[key].autoscaling_group_desired_capacity,
      Min_Size                  = module.asg[key].autoscaling_group_min_size,
      Max_Size                  = module.asg[key].autoscaling_group_max_size,
      Subnets                   = module.asg[key].autoscaling_group_vpc_zone_identifier,
      Launch_Template_Name      = module.asg[key].launch_template_name,
      Target_group_Arns         = module.asg[key].autoscaling_group_target_group_arns,
      Health_Check_Type         = module.asg[key].autoscaling_group_health_check_type,
      Health_Check_Grace_Period = module.asg[key].autoscaling_group_health_check_grace_period,
      Default_Cooldown          = module.asg[key].autoscaling_group_default_cooldown
    }
  }
}

resource "local_file" "yaml_asg" {
  count    = length(var.aws.resources.asg) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/asg.yaml"
  content  = yamlencode(local.yaml_asg)
}

# ╔════════════════════════════╗
# ║ Create NLB yaml            ║
# ╚════════════════════════════╝

locals {
  yaml_nlb = var.aws.resources.nlb == 0 ? {} : {
    for key, value in var.aws.resources.nlb : key => {
      Id                     = module.nlb[key].lb_id,
      Lb_Dns_Name            = module.nlb[key].lb_dns_name,
      Scheme                 = value.internal == false ? "Internet-facing" : "Internal",
      Http_Tcp_Listener_Arns = module.nlb[key].http_tcp_listener_arns,
      Https_Listener_Arns    = module.nlb[key].https_listener_arns,
      Security_Group_Id      = module.nlb[key].security_group_id,
      Target_Group_names     = module.nlb[key].target_group_names
    }
  }
}

resource "local_file" "yaml_nlb" {
  count    = length(var.aws.resources.nlb) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/nlb.yaml"
  content  = yamlencode(local.yaml_nlb)
}

# ╔════════════════════════════╗
# ║ Create ALB yaml            ║
# ╚════════════════════════════╝

locals {
  yaml_alb = var.aws.resources.alb == 0 ? {} : {
    for key, value in var.aws.resources.alb : key => {
      Id                     = module.alb[key].lb_id,
      Lb_Dns_Name            = module.alb[key].lb_dns_name,
      Scheme                 = value.internal == false ? "Internet-facing" : "Internal",
      Http_Tcp_Listener_Arns = module.alb[key].http_tcp_listener_arns,
      Https_Listener_Arns    = module.alb[key].https_listener_arns,
      Security_Group_Id      = module.alb[key].security_group_id,
      Target_Group_names     = module.alb[key].target_group_names
    }
  }
}

resource "local_file" "yaml_alb" {
  count    = length(var.aws.resources.alb) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/alb.yaml"
  content  = yamlencode(local.yaml_alb)
}


# ╔════════════════════════════╗
# ║ Create Kinesis yaml        ║
# ╚════════════════════════════╝

locals {
  yaml_kinesis = var.aws.resources.kinesis == 0 ? {} : {
    for key, value in var.aws.resources.kinesis : key => {
      Name           = aws_kinesis_video_stream.this[key].name,
      Device_Name    = aws_kinesis_video_stream.this[key].device_name,
      Data_Retention = aws_kinesis_video_stream.this[key].data_retention_in_hours,
      Media_Type     = aws_kinesis_video_stream.this[key].media_type,
      Version        = aws_kinesis_video_stream.this[key].version
    }
  }
}

resource "local_file" "yaml_kinesis" {
  count    = length(var.aws.resources.kinesis) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/kinesis.yaml"
  content  = yamlencode(local.yaml_kinesis)
}


# ╔════════════════════════════╗
# ║ Create WAF yaml            ║
# ╚════════════════════════════╝

locals {
  yaml_waf = var.aws.resources.waf == 0 ? {} : {
    for key, value in var.aws.resources.waf : key => {
      Name     = aws_wafv2_web_acl.this[key].name,
      Capacity = aws_wafv2_web_acl.this[key].capacity,
      Scope    = aws_wafv2_web_acl.this[key].scope,
      Rules = length(value.rules) > 0 ? [
        for rule in value.rules : {
          priority  = rule.priority
          statement = rule.statement
        }
      ] : null,
    }
  }
}

resource "local_file" "yaml_waf" {
  count    = length(var.aws.resources.waf) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/waf.yaml"
  content  = yamlencode(local.yaml_waf)
}


# ╔════════════════════════════╗
# ║ Create VPC yaml            ║
# ╚════════════════════════════╝

locals {
  yaml_vpc = var.aws.resources.vpc == 0 ? {} : {
    for key, value in var.aws.resources.vpc : key => {
      Name = module.vpc[key].name,
      Id   = module.vpc[key].vpc_id,
      Azs  = module.vpc[key].azs,
      Subnets = {
        Private_Subnets     = module.vpc[key].private_subnets,
        Public_Subnets      = module.vpc[key].public_subnets,
        Database_subnets    = module.vpc[key].database_subnets,
        Elasticache_subnets = module.vpc[key].elasticache_subnets
      }
      Nat_Gw_Ids     = module.vpc[key].natgw_ids,
      Internet_Gw_Id = module.vpc[key].igw_id
    }
  }
}

resource "local_file" "yaml_vpc" {
  count    = length(var.aws.resources.vpc) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/vpc.yaml"
  content  = yamlencode(local.yaml_vpc)
}

# ╔════════════════════════════╗
# ║ Create Cloudfront yaml     ║
# ╚════════════════════════════╝
locals {
  yaml_cloudfront = var.aws.resources.cloudfront_distributions == 0 ? {} : {
    for key, value in var.aws.resources.cloudfront_distributions : key => {
      Id          = aws_cloudfront_distribution.this[key].id,
      Domain_Name = aws_cloudfront_distribution.this[key].domain_name,
      Origin      = aws_cloudfront_distribution.this[key].origin
      Default_Cache_Behavior = {
        Cache_Policy_Id            = aws_cloudfront_distribution.this[key].default_cache_behavior[*].cache_policy_id,
        Origin_Request_Policy_Id   = aws_cloudfront_distribution.this[key].default_cache_behavior[*].origin_request_policy_id,
        Response_Headers_Policy_Id = aws_cloudfront_distribution.this[key].default_cache_behavior[*].response_headers_policy_id
      }

      Ordered_Cache_Behavior = length(aws_cloudfront_distribution.this[key].ordered_cache_behavior) > 0 ? [
        for ocb in aws_cloudfront_distribution.this[key].ordered_cache_behavior : {
          Cache_Policy_Id            = ocb.cache_policy_id,
          Response_Headers_Policy_Id = ocb.response_headers_policy_id
        }
      ] : null,
    }
  }

  yaml_cloudfront_policy = var.aws.resources.cloudfront_cache_policies == 0 ? {} : {
    for key, value in var.aws.resources.cloudfront_cache_policies : key => {
      Id   = aws_cloudfront_cache_policy.this[key].id,
      Name = aws_cloudfront_cache_policy.this[key].name
    }
  }
}

resource "local_file" "yaml_cloudfront" {
  count    = length(var.aws.resources.cloudfront_distributions) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/cloudfront.yaml"
  content  = yamlencode({ cloudfront_distributions = local.yaml_cloudfront, cloudfront_cache_policies = local.yaml_cloudfront_policy })
}

# ╔════════════════════════════╗
# ║ Create ELC Memcache yaml   ║
# ╚════════════════════════════╝
locals {
  yaml_elc_memcache = var.aws.resources.elc == 0 ? {} : {
    for key, value in var.aws.resources.elc : key => {
      Cluster_Id = aws_elasticache_cluster.this[key].cluster_id,
      Address    = aws_elasticache_cluster.this[key].cluster_address,
      Nodes      = aws_elasticache_cluster.this[key].cache_nodes,
      Engine     = aws_elasticache_cluster.this[key].engine,
      Version    = aws_elasticache_cluster.this[key].engine_version
    } if value.engine == "memcached"
  }
}

resource "local_file" "yaml_elc_memcache" {
  count    = length(local.yaml_elc_memcache) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/elc_memcache.yaml"
  content  = yamlencode(local.yaml_elc_memcache)
}


# ╔════════════════════════════╗
# ║ Create ELC Redis yaml      ║
# ╚════════════════════════════╝
locals {
  yaml_elc_redis = var.aws.resources.elc == 0 ? {} : {
    for key, value in var.aws.resources.elc : key => {
      Id                             = aws_elasticache_replication_group.this[key].id,
      Member_Clusters                = aws_elasticache_replication_group.this[key].member_clusters,
      Configuration_Endpoint_Address = aws_elasticache_replication_group.this[key].configuration_endpoint_address,
      Num_Cache_Clusters             = aws_elasticache_replication_group.this[key].num_cache_clusters,
      Num_Node_Groups                = aws_elasticache_replication_group.this[key].num_node_groups,
      Replicas_Per_Node_Group        = aws_elasticache_replication_group.this[key].replicas_per_node_group,
      Engine                         = aws_elasticache_replication_group.this[key].engine,
      Version                        = aws_elasticache_replication_group.this[key].engine_version_actual
    } if value.engine == "redis"
  }
}

resource "local_file" "yaml_elc_redis" {
  count    = length(local.yaml_elc_redis) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/elc_redis.yaml"
  content  = yamlencode(local.yaml_elc_redis)
}

# ╔════════════════════════════╗
# ║ Create EKS yaml            ║
# ╚════════════════════════════╝
locals {
  yaml_eks = var.aws.resources.eks == 0 ? {} : {
    for key, value in var.aws.resources.eks : key => {
      Cluster_Name              = module.eks[key].cluster_name,
      Cluster_Version           = module.eks[key].cluster_version,
      Cluster_Endpoint          = module.eks[key].cluster_endpoint,
      Cloudwatch_Log_Group_Name = module.eks[key].cloudwatch_log_group_name,
      Oidc_Provider_Arn         = module.eks[key].oidc_provider_arn,
      Eks_Managed_Node_Groups   = module.eks[key].eks_managed_node_groups
    }
  }
}

resource "local_file" "yaml_eks" {
  count    = length(var.aws.resources.eks) > 0 ? 1 : 0
  filename = "data/${terraform.workspace}/yaml/eks.yaml"
  content  = yamlencode(local.yaml_eks)
}