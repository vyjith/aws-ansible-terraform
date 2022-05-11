data "aws_availability_zones" "az" {
  state = "available"
}

data "aws_route53_zone" "selected" {
  name         = "vyshnavlalp.ml."
  private_zone = false
}
