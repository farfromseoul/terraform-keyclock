output "issuer" { value = "${var.issuer_origin}/realms/ai-signal" }
output "client_id" { value = keycloak_openid_client.app.client_id }
output "google_callback" { value = "${var.issuer_origin}/realms/ai-signal/broker/google/endpoint" }
output "naver_callback" { value = "${var.issuer_origin}/realms/ai-signal/broker/naver/endpoint" }
