terraform {
  required_version = ">= 1.7.0, < 2.0.0"
  required_providers {
    keycloak = { source = "keycloak/keycloak", version = "= 5.10.0" }
  }
}
provider "keycloak" {
  url       = var.admin_url
  client_id = "admin-cli"
  username  = var.admin_username
  password  = var.admin_password
  realm     = "master"
}
