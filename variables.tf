variable "aws_region"{
  type        = string
  description = "AWS region to use"
  default     = "us-west-2"
}

variable "availability_zone" {
  type        = list(string)
  description = "AWS Availability Zones to use"
  default     = ["us-west-2a","us-west-2b"]
}

variable "instance_type" {
  type        = string
  description = "The AWS EC2 tier to use for the instance."
  default     = "t2.small"
}

variable "key_name" {
  type        = string
  description = "Name of the key pair to provision the instance with."
  default     = "jab"
}

variable "aws_user"{
  type        = string
  description = "aws instance user name to connect with"
  default     = "ec2-user"
}

variable "private_key_path"{
  type        = string
  description = "full path to the filename for the private key to be used by ansible"
  default     = "/Users/jeff/.ssh/jab.pem"
}

variable "dns_name" {
  type        = string
  description = "the dns name for this deployment (sent fo flask as SERVER_NAME)"
}

variable "tls_certificate_arn" {
  type        = string
  description = "The arn of the tls/ssl certificate to attach to the load balancer"
}

variable "oidc_client_id" {
  type        = string
  description = "The client ID given to you by your identity provider (IDP)"
}

variable "preferred_url_scheme" {
  type        = string
  description = "http for non ssl, https for ssl"
  default     = "http"
}