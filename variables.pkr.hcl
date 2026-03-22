variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_name_prefix" {
  type    = string
  default = "golden-ubuntu24"
}

variable "ami_description" {
  type    = string
  default = "Golden Ubuntu 24.04 LTS with SSM and CloudWatch Agent"
}

variable "kms_key_id" {
  type    = string
  default = "alias/aws/ebs"
}

variable "volume_size" {
  type    = number
  default = 16
}
