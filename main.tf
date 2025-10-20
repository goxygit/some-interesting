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

  name               = "example"
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
      instance_types = ["t3.small"]

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
module "db_secret" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "~> 1.5"

  name        = "my-rds-secret"
  description = "RDS credentials for example app"
  
  secret_string = jsonencode({
    username = "db_user"
    password = random_password.db_password.result
  })
  depends_on = [ random_password.db_password ]
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!@#%&*()-_+="
}

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
