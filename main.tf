provider "rancher2" {
  api_url    = "${var.rancher2_api_url}"
  access_key = "${var.rancher2_access_key}"
  secret_key = "${var.rancher2_secret_key}"
}

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.aws_region}"
}

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_vpc_id" {}
variable "aws_prefix" {}
variable "aws_region" {}

variable "cpetcd_count" {}
variable "cpetcd_aws_type" {}
variable "cpetcd_volume_size" {}
variable "cpetcd_az" {}

variable "subgw_count" {}
variable "subgw_aws_type" {}
variable "subgw_volume_size" {}
variable "subgw_az" {}

variable "wrk_count" {}
variable "wrk_aws_type" {}
variable "wrk_volume_size" {}
variable "wrk_az" {}

variable "aio_count" {}
variable "aio_aws_type" {}
variable "aio_volume_size" {}
variable "aio_az" {}

variable "aws_ssh_key_name" {}

variable "rancher2_api_url" {}
variable "rancher2_access_key" {}
variable "rancher2_secret_key" {}

variable "rancher2_cluster_name" {}
variable "rancher2_cluster_description" {}
variable "rancher2_cluster_cidr" {}
variable "rancher2_service_cidr" {}
variable "rancher2_cluster_domain" {}
variable "rancher2_cluster_dns_server" {}

resource "rancher2_cluster" "cluster" {
  name = "${var.rancher2_cluster_name}"
  description = "${var.rancher2_cluster_description}"
  kind = "rke"
  rke_config {
    network {
      plugin = "canal"
    }
    services {
      kube_api { 
	    service_cluster_ip_range = "${var.rancher2_service_cidr}"
      }
      kube_controller {
        cluster_cidr = "${var.rancher2_cluster_cidr}"
	    service_cluster_ip_range = "${var.rancher2_service_cidr}"
      }
      kubelet {
	    cluster_dns_server = "${var.rancher2_cluster_dns_server}"
        cluster_domain = "${var.rancher2_cluster_domain}"
      }
    }
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "template_cloudinit_config" "rancher_cpetcd_cloudinit" {
  part {
    content_type = "text/x-shellscript"
    content      = "${file("18.09.2.sh")}"
  }
  part {
    content_type = "text/x-shellscript"
    content      = "#!/bin/sh\nusermod -aG docker ubuntu"
  }

  part {
    content_type = "text/x-shellscript"
    content      = "#!/bin/sh\n${rancher2_cluster.cluster.cluster_registration_token.0.node_command} --address awspublic --internal-address awslocal --etcd --controlplane"
  }
}

data "template_cloudinit_config" "rancher_aio_cloudinit" {
  part {
    content_type = "text/x-shellscript"
    content      = "${file("18.09.2.sh")}"
  }
  part {
    content_type = "text/x-shellscript"
    content      = "#!/bin/sh\nusermod -aG docker ubuntu"
  }

  part {
    content_type = "text/x-shellscript"
    content      = "#!/bin/sh\n${rancher2_cluster.cluster.cluster_registration_token.0.node_command} --address awspublic --internal-address awslocal --etcd --controlplane --worker"
  }
}

data "template_cloudinit_config" "rancher_subgw_cloudinit" {
  part {
    content_type = "text/x-shellscript"
    content      = "${file("18.09.2.sh")}"
  }
  part {
    content_type = "text/x-shellscript"
    content      = "#!/bin/sh\nusermod -aG docker ubuntu"
  }

  part {
    content_type = "text/x-shellscript"
    content      = "#!/bin/sh\n${rancher2_cluster.cluster.cluster_registration_token.0.node_command} --address awspublic --internal-address awslocal --worker --label submariner.io/gateway=true"
  }
}

data "template_cloudinit_config" "rancher_wrk_cloudinit" {
  part {
    content_type = "text/x-shellscript"
    content      = "${file("18.09.2.sh")}"
  }
  part {
    content_type = "text/x-shellscript"
    content      = "#!/bin/sh\nusermod -aG docker ubuntu"
  }

  part {
    content_type = "text/x-shellscript"
    content      = "#!/bin/sh\n${rancher2_cluster.cluster.cluster_registration_token.0.node_command} --address awspublic --internal-address awslocal --worker"
  }
}

resource "aws_security_group" "swisscheese" {
  name = "${var.aws_prefix}-swisscheese"
  vpc_id = "${var.aws_vpc_id}"

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

resource "aws_instance" "rancher_cpetcd" {
  count           = "${var.cpetcd_count}"
  ami             = "${data.aws_ami.ubuntu.id}"
  instance_type   = "${var.cpetcd_aws_type}"
  key_name        = "${var.aws_ssh_key_name}"
  vpc_security_group_ids = ["${aws_security_group.swisscheese.id}"]
  user_data = "${data.template_cloudinit_config.rancher_cpetcd_cloudinit.rendered}"
  availability_zone = "${var.cpetcd_az}"
  root_block_device {
    volume_size = "${var.cpetcd_volume_size}"
  }
  tags {
    Name = "${var.aws_prefix}-cpetcd-${count.index}"
  }
}

resource "aws_instance" "rancher_subgw" {
  count           = "${var.subgw_count}"
  ami             = "${data.aws_ami.ubuntu.id}"
  instance_type   = "${var.subgw_aws_type}"
  key_name        = "${var.aws_ssh_key_name}"
  vpc_security_group_ids = ["${aws_security_group.swisscheese.id}"]
  user_data = "${data.template_cloudinit_config.rancher_subgw_cloudinit.rendered}"
  availability_zone = "${var.subgw_az}"
  source_dest_check = false
  root_block_device {
    volume_size = "${var.subgw_volume_size}"
  }
  tags {
    Name = "${var.aws_prefix}-subgw-${count.index}"
  }
}

resource "aws_instance" "rancher_wrk" {
  count           = "${var.wrk_count}"
  ami             = "${data.aws_ami.ubuntu.id}"
  instance_type   = "${var.wrk_aws_type}"
  key_name        = "${var.aws_ssh_key_name}"
  vpc_security_group_ids = ["${aws_security_group.swisscheese.id}"]
  user_data = "${data.template_cloudinit_config.rancher_wrk_cloudinit.rendered}"
  availability_zone = "${var.wrk_az}"
  root_block_device {
    volume_size = "${var.wrk_volume_size}"
  }
  tags {
    Name = "${var.aws_prefix}-wrk-${count.index}"
  }
}

resource "aws_instance" "rancher_aio" {
  count           = "${var.aio_count}"
  ami             = "${data.aws_ami.ubuntu.id}"
  instance_type   = "${var.aio_aws_type}"
  key_name        = "${var.aws_ssh_key_name}"
  vpc_security_group_ids = ["${aws_security_group.swisscheese.id}"]
  user_data = "${data.template_cloudinit_config.rancher_aio_cloudinit.rendered}"
  availability_zone = "${var.aio_az}"
  root_block_device {
    volume_size = "${var.aio_volume_size}"
  }
  tags {
    Name = "${var.aws_prefix}-aio-${count.index}"
  }
}