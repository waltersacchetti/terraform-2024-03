# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Locals                                           ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
locals {
  eks_default_block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = 100
        volume_type           = "gp3"
        iops                  = 300
        encrypted             = true
        delete_on_termination = true
      }
    }
  }

  eks_default_cluster_addons = {
    aws-ebs-csi-driver = {}
    aws-efs-csi-driver = {}
    coredns            = {}
    kube-proxy         = {}
    vpc-cni = {
      # Specify the VPC CNI addon should be deployed before compute to ensure
      # the addon is configured before data plane compute resources are created
      # See README for further details
      before_compute = true
      most_recent    = true
      # configuration_values = jsonencode({
      #   env = {
      #     # Reference https://aws.github.io/aws-eks-best-practices/reliability/docs/networkmanagement/#cni-custom-networking
      #     AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
      #     ENI_CONFIG_LABEL_DEF               = "topology.kubernetes.io/zone"

      #     # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
      #     ENABLE_PREFIX_DELEGATION = "true"
      #     WARM_PREFIX_TARGET       = "1"
      #   }
      # })
    }
  }

  eks_managed_node_groups = {
    for nodegroup in flatten([
      for key, value in var.aws.resources.eks : [
        for mng_key, mng_value in value.eks_managed_node_groups : length(mng_value.subnets) > 0 ? {
          eks     = key
          mng     = mng_key
          subnets = mng_value.subnets
          vpc     = value.vpc
          } : {
          eks     = key
          mng     = mng_key
          subnets = value.subnets
          vpc     = value.vpc
        }
      ]
      ]) : "${nodegroup.eks}_${nodegroup.mng}" => {
      subnets = nodegroup.subnets
      vpc     = nodegroup.vpc
    }
  }

  eks_list_namespaces = flatten([
    for key, value in var.aws.resources.eks : [
      for namespace in value.namespaces : {
        namespace = namespace
        eks       = key
      }
    ]
  ])

  eks_map_namespaces = {
    for namespace in local.eks_list_namespaces : "${namespace.eks}_${namespace.namespace}" => namespace
  }

  eks_list_role_binding = flatten([
    for key, value in var.aws.resources.eks : [
      for role in value.role_binding : [
        for namespace in role.namespaces : {
          namespace   = namespace
          clusterrole = role.clusterrole
          username    = role.username
          eks         = key
  }]]])

  eks_map_role_binding = {
    for role in local.eks_list_role_binding : "${role.eks}_${role.namespace}_${role.clusterrole}_${role.username}" => role
  }

  eks_list_cluster_role_binding = flatten([
    for key, value in var.aws.resources.eks : [
      for role in value.cluster_role_binding : {
        clusterrole = role.clusterrole
        username    = role.username
        eks         = key
  }]])

  eks_map_cluster_role_binding = {
    for role in local.eks_list_cluster_role_binding : "${role.eks}_${role.clusterrole}_${role.username}" => role
  }
}

# ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║                                             Data                                             ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
data "aws_subnets" "eks_network" {
  for_each = var.aws.resources.eks
  filter {
    name   = "vpc-id"
    values = [module.vpc[each.value.vpc].vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = [for key in each.value.subnets : join(",", ["${local.translation_regions[var.aws.region]}-${var.aws.profile}-vpc-${each.value.vpc}-${key}"])]
  }
}

data "aws_subnets" "eks_mng_network" {
  for_each = { for k, v in local.eks_managed_node_groups : k => v if v.vpc != "ESTO_NO_EXISTE" }
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
# The module of the EKS cluster does not support to define dynamic providers

# ╔══════════════════════════════╗
# ║ Deploy EKS & Create namspaces║
# ╚══════════════════════════════╝
# resource "aws_security_group" "eks_efs" {
#   for_each = var.aws.resources.eks
#   name        = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-sg-eks-efs-${each.key}"
#   description = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-sg-eks-efs-${each.key}"
#   vpc_id      = module.vpc[each.value.vpc].vpc_id

#   ingress {
#     description      = "nfs"
#     from_port        = 2049
#     to_port          = 2049
#     protocol         = "TCP"
#     cidr_blocks      = [module.vpc[each.value.vpc].vpc_cidr_block]
#   }
# }


module "eks" {
  source   = "terraform-aws-modules/eks/aws"
  version  = "19.15.4"
  for_each = var.aws.resources.eks

  cluster_name    = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-eks-${each.key}"
  cluster_version = each.value.cluster_version

  vpc_id     = module.vpc[each.value.vpc].vpc_id
  subnet_ids = data.aws_subnets.eks_network[each.key].ids

  node_security_group_name              = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-sg-eks-node-${each.key}"
  iam_role_name                         = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-iam-role-eks-${each.key}"
  iam_role_use_name_prefix              = false
  cluster_security_group_name           = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-sg-eks-cluster-${each.key}"
  cluster_additional_security_group_ids = [module.sg[each.value.sg].security_group_id]
  cluster_encryption_policy_name        = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-eks-encryption-policy-${each.key}"

  cluster_endpoint_public_access  = each.value.public
  cluster_endpoint_private_access = true

  create_aws_auth_configmap = each.key == "main" ? length(each.value.eks_managed_node_groups) == 0 ? true : false : false
  manage_aws_auth_configmap = each.key == "main" ? true : false
  aws_auth_roles = [
    for role in each.value.aws_auth_roles : {
      rolearn  = role.arn
      username = role.username
      groups   = role.groups
    }
  ]

  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
  cluster_addons = each.value.cluster_addons == null ? local.eks_default_cluster_addons : each.value.cluster_addons

  eks_managed_node_group_defaults = {
    ami_type                   = "AL2_x86_64"
    iam_role_attach_cni_policy = true
    subnets                    = data.aws_subnets.eks_network[each.key].ids
    tags                       = merge(local.common_tags, each.value.tags)
    instance_types             = ["t3.medium"]
    disk_size                  = 100
    vpc_security_group_ids     = [module.sg[each.value.sg].security_group_id]
    # Needed by the aws-ebs-csi-driver 
    iam_role_additional_policies = each.value.iam_role_additional_policies == null ? {
      AmazonEBSCSIDriverPolicy     = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      AmazonEKS_CNI_Policy         = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      AmazonEFSCSIDriverPolicy     = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
      } : {
      for key, value in each.value.iam_role_additional_policies :
      key => strcontains(value, "arn:aws") ? value : aws_iam_policy.this[value].arn
    }
  }

  eks_managed_node_groups = {
    for name, value in each.value.eks_managed_node_groups : name => {
      name               = "${local.translation_regions[var.aws.region]}-emng-${each.key}-${name}"
      ami_type           = value.ami_type
      desired_size       = value.desired_size
      instance_types     = [value.instance_type]
      min_size           = value.min_size
      max_size           = value.max_size
      kubelet_extra_args = value.kubelet_extra_args
      subnet_ids         = data.aws_subnets.eks_mng_network["${each.key}_${name}"].ids
      tags               = merge(local.common_tags, each.value.tags, value.tags)
      block_device_mappings = value.block_device_mappings == null && value.default_block_device_mappings_cmk_key == null ? local.eks_default_block_device_mappings : value.default_block_device_mappings_cmk_key != null ? {
        # block_device_mappings by default with CMK encryption
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 100
            volume_type           = "gp3"
            iops                  = 300
            encrypted             = true
            kms_key_id            = module.kms[value.default_block_device_mappings_cmk_key].key_arn
            delete_on_termination = true
          }
        }
      } : value.block_device_mappings
      labels = merge(value.labels, { "mova/nodegroup" = name, "mova/clustername" = each.key })
      taints = value.taints
    }
  }
  tags = merge(local.common_tags, each.value.tags)
}

resource "kubernetes_namespace" "this" {
  depends_on = [module.eks]
  for_each   = local.eks_map_namespaces
  metadata {
    name = each.value.namespace
  }
}

# ╔═════════════════════════════╗
# ║ Deploy AWS ALB Controller   ║
# ╚═════════════════════════════╝

module "eks_iam_role_alb" {
  source   = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version  = "5.28.0"
  for_each = var.aws.resources.eks

  role_name                              = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-eks-iam-${each.key}"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks[each.key].oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = merge(local.common_tags, each.value.tags)
}

resource "kubernetes_service_account" "aws_load_balancer_controller" {
  for_each = var.aws.resources.eks
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
    }
    annotations = {
      "eks.amazonaws.com/role-arn"               = module.eks_iam_role_alb[each.key].iam_role_arn
      "eks.amazonaws.com/sts-regional-endpoints" = "true"
    }
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  for_each   = var.aws.resources.eks
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  depends_on = [kubernetes_service_account.aws_load_balancer_controller]
  set {
    name  = "region"
    value = var.aws.region
  }

  set {
    name  = "vpcId"
    value = module.vpc[each.value.vpc].vpc_id
  }

  set {
    name  = "image.repository"
    value = "public.ecr.aws/eks/aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "clusterName"
    value = module.eks[each.key].cluster_name
  }
}

# ╔═════════════════════════════╗
# ║ Role Bindings & Cluster     ║
# ╚═════════════════════════════╝
resource "kubernetes_role_binding" "this" {
  depends_on = [kubernetes_namespace.this]
  for_each   = local.eks_map_role_binding
  # En realidad solo puede haber un cluster de EKS pero se prepara para posible futuro
  metadata {
    name      = "${each.value.namespace}-${each.value.clusterrole}-${each.value.username}"
    namespace = each.value.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = each.value.clusterrole
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "User"
    name      = each.value.username
  }
}

resource "kubernetes_cluster_role_binding" "this" {
  depends_on = [module.eks]
  for_each   = local.eks_map_cluster_role_binding
  metadata {
    name = "${each.value.clusterrole}-${each.value.username}"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = each.value.clusterrole
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "User"
    name      = each.value.username
  }
}

# ╔═════════════════════════════╗
# ║ EKS Blueprints for mons     ║
# ╚═════════════════════════════╝
module "eks_blueprints_addons" {
  source   = "aws-ia/eks-blueprints-addons/aws"
  version  = "~> 1.0"
  for_each = var.aws.resources.eks

  cluster_name      = module.eks[each.key].cluster_name
  cluster_endpoint  = module.eks[each.key].cluster_endpoint
  cluster_version   = module.eks[each.key].cluster_version
  oidc_provider_arn = module.eks[each.key].oidc_provider_arn

  # This is required to expose Istio Ingress Gateway
  enable_aws_cloudwatch_metrics = true
  enable_aws_for_fluentbit      = true

  tags = merge(local.common_tags, each.value.tags)
}

# ╔═════════════════════════════╗
# ║ CICD Configuration          ║
# ╚═════════════════════════════╝
resource "kubernetes_namespace" "cicd" {
  depends_on = [module.eks]
  for_each   = { for k, v in var.aws.resources.eks : k => v if v.cicd }
  metadata {
    name = "devops"
  }
}

resource "kubernetes_service_account" "cicd" {
  depends_on = [kubernetes_namespace.cicd]
  for_each   = { for k, v in var.aws.resources.eks : k => v if v.cicd }
  metadata {
    name      = "cicd"
    namespace = "devops"
  }
}

resource "kubernetes_secret" "cicd" {
  depends_on = [kubernetes_service_account.cicd]
  for_each   = { for k, v in var.aws.resources.eks : k => v if v.cicd }
  metadata {
    name      = "cicd-secret"
    namespace = "devops"
    annotations = {
      "kubernetes.io/service-account.name" = "cicd"
    }
  }

  type = "kubernetes.io/service-account-token"
}

resource "kubernetes_cluster_role_binding" "cicd" {
  depends_on = [kubernetes_service_account.cicd]
  for_each   = { for k, v in var.aws.resources.eks : k => v if v.cicd }
  metadata {
    name = "devops-cicd-cluster-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "cicd"
    namespace = "devops"
  }
}

resource "local_file" "kubeconfig_cicd" {
  for_each = { for k, v in var.aws.resources.eks : k => v if v.cicd }
  filename = "data/${terraform.workspace}/eks/${each.key}/cicd.kubeconfig"
  content = templatefile("${path.module}/templates/eks-cicd.tftpl", {
    certificate = module.eks[each.key].cluster_certificate_authority_data
    host        = module.eks[each.key].cluster_endpoint
    name        = "eks-${var.aws.profile}-${each.key}-cicd"
    token       = kubernetes_secret.cicd[each.key].data.token
  })
}

# ╔═════════════════════════════╗
# ║ Export Kubeconfig           ║
# ╚═════════════════════════════╝
resource "local_file" "kubeconfig" {
  for_each = var.aws.resources.eks
  filename = "data/${terraform.workspace}/eks/${each.key}/admin.kubeconfig"
  content = templatefile("${path.module}/templates/eks-config.tftpl", {
    certificate  = module.eks[each.key].cluster_certificate_authority_data
    host         = module.eks[each.key].cluster_endpoint
    name         = "eks-${var.aws.profile}-${each.key}"
    cluster-name = "${local.translation_regions[var.aws.region]}-${var.aws.profile}-eks-${each.key}"
    region       = var.aws.region
    profile      = var.aws.profile
  })
}
