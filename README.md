# ASG rolling update using Ansible Dynamic inventory

## Introduction
Here's a project for the auto-scaling group that has a rolling update. First, I'll give you a general overview of the infrastructure that's been put in place here. For updating the files in the website application, developers have access to a Central Github repository. They will push the codes to the repository, and once the repository is updated, the new changes should be reflected automatically in the website application.

Terraform is used to build the infra. Autoscaling group has been configured with a launch configuration that includes user data to fetch the contents from the Github repository. As a result, when new instances are spun up, they will be pre-loaded with application data. A load balancer was set up at the same time to manage the traffic.

Let's say, The project is now in the testing phase, with several builds occurring for the development side, and modifications made by developers should only be reflected in the current instances, with no requirement for new instances to be spun up with the update.

We use the serial keyword to accomplish provisioning in order to save money and time. While performing the code update, the instance will not be erased or recreated if you use the serial keyword, but modifications will be applied to all instances.

## Features
 - Rolling update via Ansible Playbook
 - There is no requirement for hosts because Dynamic Inventory is configured.
 - Using IAM role so no need of AWS access key and secret key.
 

## Pre-Requests
  - Basic Knowledge in AWS services, Ansible, Terraform
  - Terrform should be installed on the master machine
  > [Terraform installation steps](https://www.terraform.io/downloads)
  - Ansible should be installed on the master machine
  > [Ansible Installation Steps](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) 
  - IAM Role with requiured policy and should be attached to Ansible master machine
   
## Modules used
  - terraform
  - ec2_instance_info
  - add_host
  - yum
  - git
  - file

## Ansible playbook
  - The Ansible playbook that will be doing the tasks specified earlier is provided below.
```sh
---
- name: "Creating AWS Infra Using Ansible through Terraform module"
  hosts: localhost
  become: true
  vars_files:
    - variables.yml

  tasks:

    - name: "Installing pip"
      yum:
        name: pip
        state: present
    
    - name: "Installing boto3"
      pip:
        name: boto3
        state: present
        
    - name: "Deployment of Terraform code"
      community.general.terraform:
        project_path: '{{ project_dir }}'
        state: present
        force_init: true

    - name: "Amazon - Fetching Ec2 Info"
      amazon.aws.ec2_instance_info:
        region: "{{ region }}"
        filters:
            "tag:aws:autoscaling:groupName" : "{{ project }}"
      register: ec2

    - name: "Amazon - Creating Dynamic Inventory"
      add_host:
        hostname: '{{ item.public_ip_address }}'
        ansible_host: '{{ item.public_ip_address }}'
        ansible_port: 22
        groups:
          - backends
        ansible_ssh_private_key_file: "./terrakey"
        ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
      with_items: "{{ ec2.instances }}"


- name: "Deployment From GitHub"
  hosts: backends
  become: true
  serial: 1
  vars_files:
    - variables.yml
  tasks:

    - name: "Package Installation"
      yum:
        name: "{{ packages }}"
        state: present

    - name: "Clonning Github Repository {{ repo }}"
      git:
        repo: "{{ repo }}"
        dest: "/var/website/"
      register: gitstatus 

    - name: "Backend off loading from elb"
      when: gitstatus.changed
      file:
        path: "/var/www/html/health.html"
        mode: 0000

    - name: "Waiting for connection draining"
      when: gitstatus.changed
      wait_for:
        timeout: 30

    - name: "Updating site contents"
      when: gitstatus.changed
      copy:
        src: "/var/website/"
        dest: "/var/www/html/"
        remote_src: true
        owner: apache
        group: apache

    - name: "Loading webserver to elb"
      when: gitstatus.changed
      file:
        path: "/var/www/html/health.html"
        mode: 0644

    - name: "Waiting for connection draining"
      when: gitstatus.changed
      wait_for:
        timeout: 20
```        
  - Playbook for storing variables
```sh
region: "ap-south-1"

project: "Shopping"
packages:
  - php
  - git
  - httpd
repo: https://github.com/vyjith/aws-elb-site

project_dir: /home/ec2-user/aws-github-terraform-ansible/
```

## Terraform scripts
  - variables.tf
```sh
variable "region" {
  default = "ap-south-1"
}

variable "access_key" {
  description = "Access key of IAM user with required privileges"
  default = "<your access key>"
}

variable "secret_key" {
  description = "Secret key of IAM user with required privileges"
  default = "<your secret key>"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "instance_ami" {
  default = "ami-0a3277ffce9146b74"
}

variable "project" {
  default = "Shopping"
}
```
  - provider.tf
```sh
provider "aws" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key
}
```

  - output.tf
```sh
data "aws_instances" "server" {
  instance_tags = {
    Name = var.project
   }
}
```
  - datasource.tf
```sh
data "aws_availability_zones" "az" {
  state = "available"
}

data "aws_route53_zone" "selected" {
  name         = "vyjithks.tk."
  private_zone = false
}
```
  - User data script for launch configuration
```sh
#!/bin/bash

echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config

yum install httpd php git -y
git clone  https://github.com/vyjith/aws-elb-site
cp -r /var/website/* /var/www/html/
chown -R apache:apache /var/www/html/*

systemctl restart httpd.service
systemctl enable httpd.service
```

  - main.tf
```sh
# -----------------------------------------------------------
# ssh key pair
# -----------------------------------------------------------
resource "aws_key_pair" "sshkey" {

  key_name   = "${var.project}-key"
  public_key = file("./terrakey.pub")
  tags = {
    Name = "${var.project}-key"
    project = var.project
  }
}
# -----------------------------------------------------------
# Security Group For Webserver Access
# -----------------------------------------------------------
resource "aws_security_group" "webserver" {
  name        = "webserver"
  description = "allows conntection to port 80 and 22 from all IPs"
  ingress {
    description      = ""
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = [ "0.0.0.0/0" ]
    ipv6_cidr_blocks = [ "::/0" ]
  }
  ingress {
    description      = ""
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = [ "0.0.0.0/0" ]
    ipv6_cidr_blocks = [ "::/0" ]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = [ "0.0.0.0/0" ]
    ipv6_cidr_blocks = [ "::/0" ]
  }
  tags = {
    Name = "${var.project}"
    project = var.project
  }
}
# -----------------------------------------------------------
# Classic Loadbalncer
# -----------------------------------------------------------
resource "aws_elb" "clb" {
  name_prefix        = "${substr(var.project, 0, 5)}-"
  security_groups    = [aws_security_group.webserver.id]
  availability_zones = [ "ap-south-1a", "ap-south-1b" ]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 2
    target              = "HTTP:80/health.html"
    interval            = 15
  }
  cross_zone_load_balancing   = true
  idle_timeout                = 60
  connection_draining         = true
  connection_draining_timeout = 5
  tags   = {
    Name = var.project
    project = var.project
  }
}

# -----------------------------------------------------------
# Route53 record addition
# -----------------------------------------------------------
resource "aws_route53_record" "site" {

  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "shopping.${data.aws_route53_zone.selected.name}"
  type    = "CNAME"
  ttl     = "5"
  records = [aws_elb.clb.dns_name]

}

# -----------------------------------------------------------
# Launch Configuration
# -----------------------------------------------------------
resource "aws_launch_configuration" "frontend" {
  name_prefix     = "${var.project}-"
  key_name = aws_key_pair.sshkey.id
  image_id        = "${var.instance_ami}"
  instance_type   = "t2.micro"
  user_data       = file("setup.sh")
  security_groups = [aws_security_group.webserver.id]
  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------
# AutoScaling Group
# -----------------------------------------------------------
resource "aws_autoscaling_group" "frontend" {
  name                      = "${var.project}"
  launch_configuration      = aws_launch_configuration.frontend.name
  min_size                  = 2
  max_size                  = 2
  desired_capacity          = 2
  health_check_grace_period = 120
  availability_zones = [ "ap-south-1a", "ap-south-1b" ]
  load_balancers            = [ aws_elb.clb.id ]
  wait_for_elb_capacity     = 2
  health_check_type         = "ELB"
  tag {
    key                 = "Name"
    value               = var.project
    propagate_at_launch = true
  }
  tag {
    key                 = "project"
    value               = var.project
    propagate_at_launch = true
  }
  lifecycle {
    create_before_destroy = true
  }
}

output "instance" {
    value = "http://${aws_elb.clb.dns_name}"
}
```

Ran ansible playbook using below commands
```sh
$ ansible-playbook main.yml --syntax-check
$ ansible-playbook main.yml
```

## Conclusion
It's an AWS infrastructure-based rolling update project that uses the ansible terrafom module and ansible playbook. 
