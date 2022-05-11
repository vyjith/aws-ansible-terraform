variable "region" {
  default = "ap-south-1"
}

variable "access_key" {
  description = "Access key of IAM user with required privileges"
  default = ""
}

variable "secret_key" {
  description = "Secret key of IAM user with required privileges"
  default = ""
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
