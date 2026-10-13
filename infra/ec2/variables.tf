variable "region" { default = "ap-northeast-2" }
variable "availability_zone" { default = "ap-northeast-2a" }
variable "name" { default = "ai-signal-keycloak" }
variable "instance_type" { default = "t3.medium" }
variable "auth_hostname" {
  type        = string
  description = "Public DNS hostname without scheme or path. Point its A record to the output EIP."
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$", var.auth_hostname))
    error_message = "Provide a lowercase public DNS hostname such as auth.example.com."
  }
}
variable "acme_email" { type = string }
variable "bootstrap_parameter_name" {
  type        = string
  default     = "/ai-signal/keycloak/bootstrap"
  description = "Existing SSM SecureString JSON: db_password, admin_password. Created manually; Terraform never reads the value."
}
variable "secret_kms_key_arn" {
  type        = string
  default     = null
  description = "Optional customer-managed KMS key ARN used for the bootstrap SSM parameter."
}
variable "keycloak_image" { default = "quay.io/keycloak/keycloak:26.8.0" }
variable "postgres_image" { default = "postgres:17.6" }
variable "caddy_image" { default = "caddy:2.10.2" }
variable "data_size_gb" { default = 20 }

variable "existing_network" {
  type        = object({ vpc_id = string, subnet_id = string })
  default     = null
  description = "Optional existing public subnet with IGW routing. Terraform does not modify its routes or VPC."
}
