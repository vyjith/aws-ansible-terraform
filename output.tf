data "aws_instances" "server" {
  instance_tags = {
    Name = var.project
   }
}
