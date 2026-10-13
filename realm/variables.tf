variable "admin_url" { default = "http://localhost:8080" }
variable "admin_username" { default = "bootstrap-admin" }
variable "admin_password" {
  type      = string
  sensitive = true
}
variable "issuer_origin" { type = string }
variable "app_origin" { type = string }
variable "local_app_origin" {
  type        = string
  default     = ""
  description = "Optional development callback origin; remove in production."
}
variable "app_client_secret" {
  type      = string
  sensitive = true
  validation {
    condition     = length(var.app_client_secret) >= 32
    error_message = "Use at least 32 random characters."
  }
}
variable "enable_google" { default = false }
variable "google_client_id" { default = "" }
variable "google_client_secret" {
  default   = ""
  sensitive = true
}
variable "enable_naver" { default = false }
variable "naver_client_id" { default = "" }
variable "naver_client_secret" {
  default   = ""
  sensitive = true
}
