mock_provider "aws" {
  mock_data "aws_subnet" {
    defaults = { vpc_id = "vpc-12345678", availability_zone = "ap-northeast-2a" }
  }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
}
variables {
  auth_hostname = "auth.example.com"
  acme_email    = "operator@example.com"
}
run "secure_ec2_plan" {
  command = plan
  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required."
  }
  assert {
    condition     = aws_ebs_volume.data.encrypted
    error_message = "Persistent storage must be encrypted."
  }
  assert {
    condition     = alltrue([for r in aws_security_group.this.ingress : contains([80, 443], r.from_port)])
    error_message = "Do not expose SSH, database, or Keycloak admin ports."
  }
}

run "reuse_existing_network" {
  command = plan
  variables {
    existing_network = { vpc_id = "vpc-12345678", subnet_id = "subnet-12345678" }
  }
  assert {
    condition     = length(aws_vpc.this) == 0 && length(aws_subnet.this) == 0 && length(aws_internet_gateway.this) == 0
    error_message = "Existing-network mode must not create or replace shared networking."
  }
  assert {
    condition     = aws_instance.this.subnet_id == "subnet-12345678" && aws_security_group.this.vpc_id == "vpc-12345678"
    error_message = "Compute must use the supplied network."
  }
}
