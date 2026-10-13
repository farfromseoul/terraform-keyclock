resource "keycloak_realm" "this" {
  realm                    = "ai-signal"
  enabled                  = true
  display_name             = "AI SIGNAL"
  registration_allowed     = false
  reset_password_allowed   = false
  login_with_email_allowed = true
  ssl_required             = "external"
  access_token_lifespan    = "5m"
  sso_session_idle_timeout = "30m"
  sso_session_max_lifespan = "8h"
  security_defenses {
    brute_force_detection {
      permanent_lockout        = false
      max_login_failures       = 5
      wait_increment_seconds   = 60
      max_failure_wait_seconds = 900
    }
  }
}
resource "keycloak_openid_client" "app" {
  realm_id                     = keycloak_realm.this.id
  client_id                    = "page-manager"
  name                         = "AI SIGNAL Research Desk"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  client_secret                = var.app_client_secret
  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
  pkce_code_challenge_method   = "S256"
  valid_redirect_uris          = concat(["${var.app_origin}/auth/callback"], var.local_app_origin == "" ? [] : ["${var.local_app_origin}/auth/callback"])
  web_origins                  = []
  full_scope_allowed           = false
}
resource "keycloak_role" "app" {
  for_each  = toset(["admin", "editor", "viewer"])
  realm_id  = keycloak_realm.this.id
  client_id = keycloak_openid_client.app.id
  name      = each.key
}
resource "keycloak_openid_user_client_role_protocol_mapper" "roles" {
  realm_id                    = keycloak_realm.this.id
  client_id                   = keycloak_openid_client.app.id
  name                        = "page-manager-roles"
  claim_name                  = "page_roles"
  client_id_for_role_mappings = keycloak_openid_client.app.client_id
  multivalued                 = true
  add_to_id_token             = true
  add_to_access_token         = true
  add_to_userinfo             = false
}
resource "keycloak_openid_client_scope" "roles" {
  realm_id = keycloak_realm.this.id
  name     = "page-manager-role-scope"
}
resource "keycloak_generic_role_mapper" "roles" {
  for_each        = keycloak_role.app
  realm_id        = keycloak_realm.this.id
  client_scope_id = keycloak_openid_client_scope.roles.id
  role_id         = each.value.id
}
resource "keycloak_openid_client_default_scopes" "app" {
  realm_id       = keycloak_realm.this.id
  client_id      = keycloak_openid_client.app.id
  default_scopes = ["profile", keycloak_openid_client_scope.roles.name]
}
resource "keycloak_oidc_google_identity_provider" "google" {
  count          = var.enable_google ? 1 : 0
  realm          = keycloak_realm.this.id
  client_id      = var.google_client_id
  client_secret  = var.google_client_secret
  trust_email    = false
  store_token    = false
  default_scopes = "openid profile email"
}
resource "keycloak_oidc_identity_provider" "naver" {
  count              = var.enable_naver ? 1 : 0
  realm              = keycloak_realm.this.id
  alias              = "naver"
  display_name       = "네이버"
  client_id          = var.naver_client_id
  client_secret      = var.naver_client_secret
  authorization_url  = "https://nid.naver.com/oauth2/authorize"
  token_url          = "https://nid.naver.com/oauth2/token"
  jwks_url           = "https://nid.naver.com/oauth2/jwks"
  issuer             = "https://nid.naver.com"
  default_scopes     = "openid profile"
  validate_signature = true
  disable_user_info  = true
  trust_email        = false
  store_token        = false
  extra_config       = { clientAuthMethod = "client_secret_post", pkceEnabled = "true", pkceMethod = "S256" }
}
