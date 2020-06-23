variable "availability_zone" {
  type        = string
  description = "AWS Availability Zone to use"
  default     = "us-west-2a"
}

variable "instance_type" {
  type        = string
  description = "The AWS EC2 tier to use for the DB instances."
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
  default     ="/Users/jeff/.ssh/jab.pem"
}
