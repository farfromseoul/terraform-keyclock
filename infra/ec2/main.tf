data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
resource "aws_vpc" "this" {
  count                = var.existing_network == null ? 1 : 0
  cidr_block           = "10.87.0.0/24"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = var.name }
}
resource "aws_subnet" "this" {
  count             = var.existing_network == null ? 1 : 0
  vpc_id            = aws_vpc.this[0].id
  cidr_block        = "10.87.0.0/26"
  availability_zone = var.availability_zone
}
resource "aws_internet_gateway" "this" {
  count  = var.existing_network == null ? 1 : 0
  vpc_id = aws_vpc.this[0].id
}
resource "aws_route_table" "this" {
  count  = var.existing_network == null ? 1 : 0
  vpc_id = aws_vpc.this[0].id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }
}
resource "aws_route_table_association" "this" {
  count          = var.existing_network == null ? 1 : 0
  subnet_id      = aws_subnet.this[0].id
  route_table_id = aws_route_table.this[0].id
}
data "aws_subnet" "existing" {
  count = var.existing_network == null ? 0 : 1
  id    = var.existing_network.subnet_id
}
locals {
  vpc_id            = var.existing_network == null ? aws_vpc.this[0].id : var.existing_network.vpc_id
  subnet_id         = var.existing_network == null ? aws_subnet.this[0].id : var.existing_network.subnet_id
  availability_zone = var.existing_network == null ? var.availability_zone : data.aws_subnet.existing[0].availability_zone
}
resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  vpc_id      = local.vpc_id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS OIDC through Caddy"
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "ACME HTTP challenge and HTTPS redirect"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_iam_role" "this" {
  name_prefix        = "${var.name}-"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "bootstrap" {
  role   = aws_iam_role.this.id
  policy = jsonencode({ Version = "2012-10-17", Statement = concat([{ Effect = "Allow", Action = ["ssm:GetParameter"], Resource = "arn:${data.aws_partition.current.partition}:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.bootstrap_parameter_name}" }], var.secret_kms_key_arn == null ? [] : [{ Effect = "Allow", Action = ["kms:Decrypt"], Resource = var.secret_kms_key_arn }]) })
}
resource "aws_iam_instance_profile" "this" { role = aws_iam_role.this.name }
resource "aws_ebs_volume" "data" {
  availability_zone = local.availability_zone
  size              = var.data_size_gb
  type              = "gp3"
  encrypted         = true
  tags              = { Name = "${var.name}-data" }
  lifecycle { prevent_destroy = true }
}
resource "aws_instance" "this" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.this.name
  metadata_options { http_tokens = "required" }
  credit_specification { cpu_credits = "standard" }
  lifecycle {
    precondition {
      condition     = var.existing_network == null ? true : data.aws_subnet.existing[0].vpc_id == var.existing_network.vpc_id
      error_message = "The existing subnet must belong to the supplied VPC."
    }
  }
  root_block_device {
    volume_size = 16
    volume_type = "gp3"
    encrypted   = true
  }
  user_data_replace_on_change = true
  user_data                   = templatefile("${path.module}/user-data.sh.tftpl", { region = var.region, parameter = var.bootstrap_parameter_name, volume_id = replace(aws_ebs_volume.data.id, "-", ""), hostname = var.auth_hostname, email = var.acme_email, keycloak_image = var.keycloak_image, postgres_image = var.postgres_image, caddy_image = var.caddy_image })
  tags                        = { Name = var.name }
  depends_on                  = [aws_route_table_association.this, aws_iam_role_policy.bootstrap, aws_iam_role_policy_attachment.ssm]
}
resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.this.id
}
resource "aws_eip" "this" { domain = "vpc" }
resource "aws_eip_association" "this" {
  instance_id   = aws_instance.this.id
  allocation_id = aws_eip.this.id
}
