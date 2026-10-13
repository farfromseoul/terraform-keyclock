mock_provider "keycloak" {}
variables {
  issuer_origin        = "https://auth.example.com"
  app_origin           = "https://pages.example.com"
  admin_password       = "test-not-used-no-network"
  app_client_secret    = "test-only-32-character-secret-value"
  enable_naver         = true
  naver_client_id      = "test-client"
  naver_client_secret  = "test-secret"
  enable_google        = true
  google_client_id     = "test-client"
  google_client_secret = "test-secret"
}
run "oidc_contract" {
  command = plan
  assert {
    condition     = keycloak_openid_client.app.pkce_code_challenge_method == "S256" && !keycloak_openid_client.app.direct_access_grants_enabled
    error_message = "Use PKCE code flow; no password grant for the app."
  }
  assert {
    condition     = keycloak_oidc_identity_provider.naver[0].validate_signature && !keycloak_oidc_identity_provider.naver[0].trust_email
    error_message = "Validate Naver signatures without auto-trusting email."
  }
  assert {
    condition     = keycloak_openid_user_client_role_protocol_mapper.roles.claim_name == "page_roles" && keycloak_openid_user_client_role_protocol_mapper.roles.add_to_id_token
    error_message = "App must receive its explicit role claim in ID tokens."
  }
}
