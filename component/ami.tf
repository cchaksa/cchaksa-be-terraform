data "aws_ami" "app" {
  count = var.enable_app_stack && var.app_ami_id == null ? 1 : 0

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
