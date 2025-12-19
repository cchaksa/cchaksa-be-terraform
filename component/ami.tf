data "aws_ami" "app" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["cchaksa-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}