provider "rancher2" {
  api_url    = var.rancher2_api_url
  token_key = var.rancher2_token
}

provider "aws" {
  shared_credentials_file = var.aws_credentials_file
  region     = var.aws_region
}

variable "aws_credentials_file" {}

variable "aws_vpc_id" {}
variable "aws_prefix" {}
variable "aws_region" {}
variable "aws_ami_id" {}

variable "master_count" {}
variable "master_aws_type" {}
variable "master_volume_size" {}
variable "master_az" {}

variable "wrk_count" {}
variable "wrk_aws_type" {}
variable "wrk_volume_size" {}
variable "wrk_az" {}

variable "aws_ssh_key_name" {}

variable "rancher2_api_url" {}
variable "rancher2_token" {}

variable "rancher2_cluster_name" {}
variable "rancher2_cluster_description" {}
variable "rancher2_cluster_cidr" {}
variable "rancher2_service_cidr" {}
variable "rancher2_cluster_domain" {}
variable "rancher2_cluster_dns_server" {}

resource "rancher2_cluster" "cluster" {
  name = var.rancher2_cluster_name
  description = var.rancher2_cluster_description
  rke_config {
    network {
      plugin = "canal"
    }
    services {
      kube_api { 
	    service_cluster_ip_range = var.rancher2_service_cidr
      }
      kube_controller {
        cluster_cidr = var.rancher2_cluster_cidr
	    service_cluster_ip_range = var.rancher2_service_cidr
      }
      kubelet {
	    cluster_dns_server = var.rancher2_cluster_dns_server
        cluster_domain = var.rancher2_cluster_domain
      }
    }
  }
}

data "template_cloudinit_config" "rancher_master_cloudinit" {
  part {
    content_type = "text/x-shellscript"
    content      = "#!/bin/sh\n${rancher2_cluster.cluster.cluster_registration_token.0.node_command} --address awspublic --internal-address awslocal --etcd --controlplane"
  }
}

data "template_cloudinit_config" "rancher_wrk_cloudinit" {
  part {
    content_type = "text/x-shellscript"
    content      = "#!/bin/sh\n${rancher2_cluster.cluster.cluster_registration_token.0.node_command} --address awspublic --internal-address awslocal --worker"
  }
}

resource "aws_security_group" "swisscheese" {
  name = "${var.aws_prefix}-swisscheese"
  vpc_id = var.aws_vpc_id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [
      "0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [
    "0.0.0.0/0"
    ]
  }

}

resource "aws_instance" "rancher_master" {
  count           = var.master_count
  ami             = var.aws_ami_id
  instance_type   = var.master_aws_type
  key_name        = var.aws_ssh_key_name
  vpc_security_group_ids = [aws_security_group.swisscheese.id]
  user_data = data.template_cloudinit_config.rancher_master_cloudinit.rendered
  availability_zone = var.master_az
  root_block_device {
    volume_size = var.master_volume_size
  }
  tags = {
    Name = "${var.aws_prefix}-master-${count.index}"
  }
}

resource "aws_instance" "rancher_wrk" {
  count           = var.wrk_count
  ami             = var.aws_ami_id
  instance_type   = var.wrk_aws_type
  key_name        = var.aws_ssh_key_name
  vpc_security_group_ids = [aws_security_group.swisscheese.id]
  user_data = data.template_cloudinit_config.rancher_wrk_cloudinit.rendered
  availability_zone = var.wrk_az
  root_block_device {
    volume_size = var.wrk_volume_size
  }
  tags = {
    Name = "${var.aws_prefix}-wrk-${count.index}"
  }
}