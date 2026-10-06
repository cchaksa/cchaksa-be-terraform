variable "environment" {
  description = "Deployment environment. This module is instantiated only for prod."
  type        = string
}

variable "aws_region" {
  description = "AWS region used in the globally unique backup bucket name."
  type        = string
}
