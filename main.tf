module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "devOpsik"
  cidr = "10.0.0.0/16"

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway = true
  enable_vpn_gateway = false
  single_nat_gateway = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "dev"
  kubernetes_version = "1.33"
addons = {
    coredns                = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy             = {}
    vpc-cni                = {
      before_compute = true
    }
  }

  # Optional
  endpoint_public_access = true

  # Optional: Adds the current caller identity as an administrator via cluster access entry
  enable_cluster_creator_admin_permissions = true
  
  compute_config = {
  enabled = false
}


  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets
    eks_managed_node_groups = {
    example = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]
      capacity_type  = "SPOT"

      min_size     = 2
      max_size     = 2
      desired_size = 2
    }


    }
  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}
module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  cluster_name = module.eks.cluster_name

  # Attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}
resource "kubernetes_namespace" "monitoring" {
    provider = kubernetes.eks
  metadata {
    name = "monitoring"
  }
}

resource "helm_release" "kube_prometheus_stack" {
  provider   = helm.eks   # если у Helm provider есть alias eks
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "78.3.2"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  create_namespace = false

  set = [
    { name = "grafana.adminUser", value = "admin" },
    { name = "grafana.adminPassword", value = "admin123" },
    { name = "grafana.service.type", value = "LoadBalancer" },
    { name = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues", value = "false" }
  ]
}
# module "db_secret" {
#   source  = "terraform-aws-modules/secrets-manager/aws"
#   version = "2.0.0"

#   name        = "my-rds-secret3"
#   description = "RDS credentials for example app"
#   recovery_window_in_days = 0
#   secret_string = jsonencode({
#     username = "db_user"
#     password = random_password.db_password.result
#   })
#   depends_on = [ module.eks ]
# }

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!@#%&*()-_+="
}
# Создаем namespace для ArgoCD
resource "kubernetes_namespace" "argocd" {
  provider = kubernetes.eks
  metadata {
    name = "argocd"
  }
}

# Генерируем случайный пароль администратора
resource "random_password" "argocd_admin" {
  length           = 16
  special          = true
  override_special = "!@#%&*()-_+="
}

# Создаем секрет в AWS Secrets Manager
module "argocd_secret" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "2.0.1"

  name        = "argocd-admin-password23"
  description = "Admin password for ArgoCD UI"
  recovery_window_in_days = 0

  secret_string = jsonencode({
    username = "admin"
    password = random_password.argocd_admin.result
  })
  depends_on = [random_password.argocd_admin, module.eks]
}

# Устанавливаем ArgoCD через Helm
# resource "helm_release" "argocd" {
#   provider = helm.eks
#   name       = "argo-cd"
#   repository = "https://argoproj.github.io/argo-helm"
#   chart      = "argo-cd"
#   version    = "9.0.3"
#   namespace  = kubernetes_namespace.argocd.metadata[0].name

#   create_namespace = false

#   # Конфигурация ArgoCD без публичного доступа
#   set = [
#     { name = "server.service.type", value = "ClusterIP" },
#     { name = "server.insecure", value = "true" },
#   ]

#   # Пробрасываем сгенерированный пароль в Secret Kubernetes
#   set_sensitive = [
#     {
#       name  = "configs.secret.argocdServerAdminPassword"
#       value = bcrypt(random_password.argocd_admin.result)
#     }
#   ]

#   depends_on = [
#     kubernetes_namespace.argocd,
#     module.argocd_secret
#   ]
# }
resource "kubernetes_namespace" "web" {
  provider = kubernetes.eks
  metadata {
    name = "web"
  }
}

resource "aws_ecr_repository" "my_site" {
  name                 = "my-site"
  image_tag_mutability = "MUTABLE"
}

data "aws_iam_policy_document" "jenkins_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:jenkins:jenkins"]
    }
  }
}

resource "aws_iam_role" "jenkins" {
  name = "jenkins-irsa-${module.eks.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.jenkins_assume.json
}

resource "aws_iam_role_policy_attachment" "jenkins_ecr" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}
resource "kubernetes_namespace" "jenkins" {
    provider = kubernetes.eks
  metadata { name = "jenkins" }
}
resource "random_password" "jenkins" {
  length           = 16
  special          = true
  override_special = "!@#%&*()-_+="
}

resource "helm_release" "jenkins" {
  provider = helm.eks
  name       = "jenkins"
  namespace  = kubernetes_namespace.jenkins.metadata[0].name
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  version    = "5.8.104"

  values = [
  <<EOF
controller:
  admin:
    username: admin
    password: ${random_password.jenkins.result}
  serviceType: LoadBalancer
persistence:
  enabled: false
EOF
]

}

# istio, jenkins 

# module "rds" {
#   source = "terraform-aws-modules/rds/aws"

#   identifier = "devopsik-db"

#   engine            = "mysql"
#   engine_version    = "8.0"
#   instance_class    = "db.t3.medium"
#   allocated_storage = 20
#   storage_type      = "gp3"

#   db_name     = "usersdb"
#   username = jsondecode(module.db_secret.secret_string)["username"]
#   password = jsondecode(module.db_secret.secret_string)["password"]
#   port     = 3306

#   multi_az          = true
#   publicly_accessible = false

#   vpc_security_group_ids = [module.vpc.default_security_group_id]
#   subnet_ids             = module.vpc.private_subnets
#   create_db_subnet_group = true

#   family               = "mysql8.0"        # для parameter group
#   major_engine_version = "8.0"            # для option group


#   backup_retention_period   = 7
#   auto_minor_version_upgrade = true
#   deletion_protection       = false  # можно включить для продакшена

#   monitoring_interval    = 30
#   create_monitoring_role = true
#   monitoring_role_name   = "devopsik-rds-monitoring-role"

#   tags = {
#     Environment = "dev"
#     Terraform   = "true"
#   }
# }
