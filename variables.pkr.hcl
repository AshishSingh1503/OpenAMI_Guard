variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "pipeline_name" {
  type    = string
  default = "openami-guard"
}

variable "image_name" {
  type    = string
  default = "golden-ubuntu24"
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

variable "source_ami_name_pattern" {
  type    = string
  default = "ubuntu/images/hvm-ssd/ubuntu-*-24.04-amd64-server-*"
}

variable "source_ami_owner" {
  type    = string
  default = "099720109477"
}

variable "source_ami_ssh_username" {
  type    = string
  default = "ubuntu"
}

variable "source_ami_virtualization_type" {
  type    = string
  default = "hvm"
}

variable "source_ami_root_device_type" {
  type    = string
  default = "ebs"
}

variable "kms_key_id" {
  type    = string
  default = "alias/aws/ebs"
}

variable "volume_size" {
  type    = number
  default = 16
}
