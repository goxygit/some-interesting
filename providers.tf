provider "aws" {
  region  = "eu-central-1"
  profile = "default"  
}


data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
    depends_on = [module.eks]

}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
    depends_on = [module.eks]

}

provider "kubernetes" {
  alias                  = "eks"
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}
provider "helm" {
  alias = "eks"
  kubernetes = {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}
