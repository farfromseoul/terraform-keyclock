output "instance_id" { value = aws_instance.this.id }
output "public_ip" { value = aws_eip.this.public_ip }
output "issuer" { value = "https://${var.auth_hostname}/realms/ai-signal" }
output "data_volume_id" { value = aws_ebs_volume.data.id }
output "admin_access" { value = "Use AWS SSM port forwarding: localhost:8080 -> instance:8080. No SSH key or public admin endpoint." }
