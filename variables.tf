variable "vpc_cidr" {
  description = "CIDR For VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR For public subnets"
  default     = ["10.0.1.0/24","10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR For private subnets"
  default     = ["10.0.2.0/24","10.0.4.0/24"]
}

variable "availability_zones" {
  description = "List of AZs"
  default     = ["eu-central-1a","eu-central-1b"]
}

variable "cluster_name" {
  default = "devops-cluster"
}

variable "region" {
  default = "eu-central-1"
}