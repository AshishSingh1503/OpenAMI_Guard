packer {
  required_plugins {
    amazon = {
      source = "github.com/hashicorp/amazon"
      version = ">= 1.0.0"
    }
  }
}

source "amazon-ebs" "ubuntu" {
  region                  = var.region
  source_ami_filter {
    filters = {
      name = "ubuntu/images/hvm-ssd/ubuntu-*-24.04-amd64-server-*"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical
  }
  instance_type           = var.instance_type
  ssh_username            = "ubuntu"
  ami_name                = "${var.ami_name_prefix}-{{timestamp}}"
  ami_description         = var.ami_description
  encrypt_boot            = true
  kms_key_id              = var.kms_key_id
  tags = {
    "Name"      = "GoldenUbuntu24"
    "CreatedBy" = "Packer"
    "Version"   = "{{timestamp}}"
    "Pipeline"  = "self-healing-ami"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = var.volume_size
    volume_type = "gp3"
    delete_on_termination = true
  }
}

build {
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "shell" {
    scripts = [
      "scripts/bootstrap.sh",
      "scripts/harden.sh",
      "scripts/validate.sh"
    ]
  }

  post-processor "manifest" {
    output = "manifest.json"
  }
}
