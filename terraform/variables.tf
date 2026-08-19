variable "student_handle" {
  description = "Your short handle. Prefixes every resource name so a shared account stays sane. Lowercase letters/digits/hyphens only."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,12}$", var.student_handle))
    error_message = "student_handle must be 2-12 chars, lowercase letters, digits or hyphens."
  }
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "cluster_version" {
  description = "EKS control plane version. Verify with: aws eks describe-cluster-versions --region ap-south-1"
  type        = string
  default     = "1.33"
}

variable "node_instance_type" {
  description = "Worker instance type. t3.large gives enough memory for argocd + nginx + prometheus + flagger."
  type        = string
  default     = "t3.large"
}

variable "node_desired_size" {
  description = "Worker count."
  type        = number
  default     = 2
}

variable "vpc_cidr" {
  description = "CIDR for the lab VPC."
  type        = string
  default     = "10.42.0.0/16"
}
