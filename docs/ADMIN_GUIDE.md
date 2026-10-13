# 관리자 설치·운영 가이드

이 문서는 사용자가 직접 설치하는 절차다. 이번 작업에서 AWS apply나 Cloudflare 배포는 수행하지 않는다. 모든 example.com, 이메일, ID는 실제 값으로 바꾼다. IaC 저장소: https://github.com/farfromseoul/terraform-keyclock

## 0. 준비물과 순서

- AWS 계정, AWS CLI v2와 로그인된 관리용 profile, Session Manager plugin.
- Terraform >=1.7 (검증 버전 1.13.4), Git, Node >=22.12, npm.
- 소유한 도메인의 `auth.example.com` DNS 수정 권한. 앱은 workers.dev 주소도 가능하다.
- Cloudflare Workers/D1 권한. Google·네이버 개발자 계정은 해당 로그인 활성화 때 필요하다.
- AWS EC2/VPC/EBS/EIP/IAM 생성 권한 및 iam:PassRole, 관리자 SSM 세션 시작 권한이 필요하다. 런타임 EC2 역할은 Terraform이 제한된 SSM 권한으로 만든다.

순서: 비밀 준비 → EC2 Terraform → DNS/TLS → SSM 관리자 연결 → realm Terraform → 앱 D1/secret/배포 → 사용자 역할 → 소셜 로그인 활성화 → 검증.

## 1. 부팅 비밀을 AWS SSM에 준비

AWS Systems Manager → Parameter Store에서 `/ai-signal/keycloak/bootstrap` 이름의 **SecureString**을 만든다. 값은 아래 구조의 JSON이다. 두 비밀번호는 각각 `openssl rand -hex 32`로 독립 생성하여 비밀번호 관리자에 보관한다.

```json
{"db_password":"실제_랜덤값_24자이상","admin_password":"다른_실제_랜덤값_24자이상"}
```

실제 값에는 영문·숫자·`_`·`-`만 사용한다. 예시 한글 문자열은 적용할 수 없다. 커스텀 KMS 키를 쓰면 키 정책에서 EC2 역할의 복호화를 허용하고 `secret_kms_key_arn`을 지정한다. Terraform은 Parameter 값 자체를 조회하지 않는다.

## 2. EC2 생성 — 비용 발생 단계

```bash
git clone https://github.com/farfromseoul/terraform-keyclock.git
cd terraform-keyclock
# PR 병합 전 테스트라면: git switch feature/keycloak-ec2-research-desk
cp infra/ec2/terraform.tfvars.example infra/ec2/terraform.tfvars
# auth_hostname, acme_email, region/AZ를 수정
terraform -chdir=infra/ec2 init
terraform -chdir=infra/ec2 fmt -check
terraform -chdir=infra/ec2 validate
terraform -chdir=infra/ec2 plan -out=deploy.tfplan
terraform -chdir=infra/ec2 apply deploy.tfplan
terraform -chdir=infra/ec2 output
```

기본은 서울 ap-northeast-2 / ap-northeast-2a / t3.medium, root 16GB와 별도 DB EBS 20GB다. region을 바꾸면 AZ도 함께 바꾼다. 인스턴스 유형은 x86_64를 사용한다. Graviton으로 바꾸려면 AMI와 Compose 바이너리 아키텍처도 함께 변경해야 한다.

부팅 스크립트가 Docker·Compose를 설치하고 EBS를 마운트한 뒤 SSM 비밀을 읽어 Keycloak/PostgreSQL/Caddy를 시작한다. EBS 연결·패키지 다운로드 때문에 몇 분 소요될 수 있다. Terraform apply 성공은 애플리케이션 준비 완료를 뜻하지 않는다.

### 기존 VPC/서브넷을 사용하는 경우

미리 네트워크를 만들 필요는 없지만, 이미 있다면 tfvars에 아래를 추가한다.

```hcl
existing_network = {
  vpc_id = "vpc-실제ID"
  subnet_id = "subnet-실제ID"
}
```

같은 리전의 퍼블릭 서브넷이어야 하며 해당 route table에 `0.0.0.0/0 → Internet Gateway`가 있어야 한다. DNS 해석, NACL 응답 트래픽과 외부 443 통신을 허용한다. Terraform은 VPC 소속을 검증하고 서브넷 AZ를 조회하지만 route/NACL까지 자동 검증하지 않는다. 기존 VPC·IGW·라우팅은 수정하지 않으며 새 SG·EC2·EIP·EBS·IAM만 생성한다. 프라이빗 서브넷은 이 직접 HTTPS 구성에 맞지 않는다. 생성 후 모드 전환은 별도 마이그레이션 작업으로 취급한다.

기본 t3.medium은 2 vCPU·4GiB이며 Keycloak·PostgreSQL·Caddy가 같은 EC2에서 컨테이너로 실행된다. 고가용성 목적의 권장치가 아니라 개인/소규모 실험의 시작값이다. T3 CPU credits는 standard로 고정하여 Unlimited의 추가 CPU credit 과금을 피한다. credit 고갈 시 성능이 제한될 수 있다. 인스턴스 비용 자체가 없어지는 것은 아니다.

## 3. DNS와 TLS

DNS A 레코드 `auth.example.com`을 Terraform public_ip에 연결한다. Cloudflare DNS를 쓴다면 초기 검증은 **DNS only**로 진행한다. 80/443을 통해 Caddy가 인증서를 자동 발급한다. Cloudflare Proxy를 켜려면 정상 인증서를 확인한 뒤 Full (strict)를 사용한다. Flexible은 사용하지 않는다.

```bash
curl -I https://auth.example.com
curl -i https://auth.example.com/admin/
```

`/admin/`은 공개 경로에서 404가 맞다. realm 생성 전에는 ai-signal discovery도 404일 수 있다. EC2 보안 그룹에는 22/8080/5432를 열지 않는다.

## 4. 관리자 접속 — SSM 포트 포워딩

아래 INSTANCE_ID를 `terraform -chdir=infra/ec2 output -raw instance_id` 결과로 바꾼다.

```bash
aws ssm start-session \
  --region ap-northeast-2 \
  --target INSTANCE_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

이 터미널을 유지한 채 `http://localhost:8080/admin/`에 접속한다. 초기 사용자 `bootstrap-admin`, 비밀번호는 SSM의 admin_password다. Terraform realm도 이 포워딩 주소를 사용한다. 공개 hostname은 HTTPS, 관리자 hostname은 localhost:8080으로 의도적으로 분리했다.

EC2 내부 확인은 별도 터미널에서 `aws ssm start-session --target INSTANCE_ID --region ap-northeast-2`로 접속하고 아래를 실행한다.

```bash
sudo systemctl status keycloak-stack
sudo cloud-init status --long
sudo tail -n 80 /var/log/cloud-init-output.log
sudo docker compose --project-directory /srv/keycloak ps
sudo docker compose --project-directory /srv/keycloak logs --tail=80 keycloak
```

`.env`, `docker inspect`, bootstrap 비밀을 채팅/CI 로그로 출력하지 않는다. 로컬 8080이 이미 사용 중이면 그 프로세스를 종료하거나 포워딩·KC_HOSTNAME_ADMIN·realm admin_url을 같은 포트로 함께 바꿔야 한다.

## 5. Realm/client/roles 생성

앱의 최종 origin을 먼저 정한다. workers.dev를 사용할 경우 Cloudflare 계정의 정확한 서브도메인을 확인한다. `https://ai-signal-page-manager.YOUR-SUBDOMAIN.workers.dev` 또는 앱 커스텀 도메인을 사용한다.

```bash
cp realm/terraform.tfvars.example realm/terraform.tfvars
# issuer_origin=https://auth.example.com
# app_origin=앱의 최종 HTTPS origin (마지막 / 없음)
# 초기에는 enable_google/enable_naver=false
```

비밀은 셸 히스토리에 직접 쓰지 말고 비밀번호 관리자나 셸의 숨김 입력 기능으로 환경 변수에 설정한다. 아래 예는 Bash에서 실행한다.

```bash
bash
read -rs -p 'Keycloak admin password: ' TF_VAR_admin_password; echo
export TF_VAR_admin_password
read -rs -p 'App client secret (32+ random characters): ' TF_VAR_app_client_secret; echo
export TF_VAR_app_client_secret
terraform -chdir=realm init
terraform -chdir=realm validate
terraform -chdir=realm plan -out=realm.tfplan
terraform -chdir=realm apply realm.tfplan
```

app_client_secret은 별도로 생성한 랜덤 비밀이며 Cloudflare secret과 반드시 동일해야 한다. 적용 후 민감한 plan 파일을 안전하게 제거한다. `sensitive=true`는 출력 마스킹일 뿐 **realm state에는 비밀이 저장된다**. 로컬 state를 암호화된 디스크/제한된 권한으로 보관하고 Git에 올리지 않는다. 팀 운영 시 S3 암호화·버전 관리·잠금 backend를 별도 구성한다.

검증:
```bash
curl -fsS https://auth.example.com/realms/ai-signal/.well-known/openid-configuration
```
issuer가 정확히 `https://auth.example.com/realms/ai-signal`인지 확인한다. `admin`은 page-manager 앱 역할이며 Keycloak 관리 콘솔 권한과 다르다.

bootstrap 계정은 초기 설정용이다. 별도의 영구 Keycloak 관리자를 생성·접속 검증한 뒤 임시 계정을 제거하고, 후속 realm 적용에는 영구 관리자 또는 제한된 관리용 service account 구성을 사용한다. bootstrap 비밀번호 환경 변수만 바꿔도 기존 사용자 비밀번호가 변경되지는 않는다.

## 6. Cloudflare 앱 설치와 배포

AI-News-Crawler에서:
```bash
npm ci
npm run check
npx wrangler login
npx wrangler d1 create ai-signal-pages
```

반환된 database_id를 `wrangler.page-manager.jsonc`의 placeholder에 넣는다. 기존 ai-sig DB ID를 재사용하지 않는다. vars의 APP_ORIGIN/OIDC_ISSUER/NEWS_API_ORIGIN을 실제 환경과 맞춘다. 비밀은 vars에 넣지 않는다.

```bash
npx wrangler d1 migrations apply ai-signal-pages --remote --config wrangler.page-manager.jsonc
npx wrangler secret put OIDC_CLIENT_SECRET --config wrangler.page-manager.jsonc
npm run deploy:pages
```

프롬프트에 realm의 app_client_secret을 입력한다. 기존 GitHub 배포 workflow는 이 별도 Worker를 배포하지 않는다. 수동 배포 명령을 명시적으로 사용한다. 앱 최초 배포·secret 저장 순서에서 Worker 생성 확인이 필요하면 먼저 `npm run deploy:pages`로 정적 앱을 만든 뒤 secret을 저장한다. secret 미설정 상태의 로그인은 실패하도록 되어 있다.

커스텀 도메인을 쓰면 Cloudflare Worker 설정에서 도메인을 연결하고 APP_ORIGIN과 realm app_origin을 동시에 맞춘다. 도메인 변경 후에는 realm Terraform과 Worker를 둘 다 반영해야 한다.

## 7. 최초 앱 사용자와 역할

Keycloak ai-signal realm → Users에서 테스트 사용자를 생성하고 임시 비밀번호를 지정한다. 사용자 Role mapping → Assign role → Filter by clients → page-manager의 admin/editor/viewer 중 하나를 선택한다. 첫 관리자는 본인에게만 admin을 부여한다. 앱의 `/auth/login`으로 들어가 로그인을 확인한다.

소셜 사용자는 첫 로그인 시 Keycloak 사용자가 생성될 수 있지만 앱 역할은 없다. 관리자가 해당 사용자에게 역할을 부여한 뒤 앱에 다시 로그인하게 한다. 기본 realm role이나 이메일 문자열로 앱 admin을 부여하지 않는다.

## 8. Google 연결

Google Cloud Console의 OAuth 설정에서 프로젝트·동의 화면·Web application 클라이언트를 준비한다. 테스트 상태에서는 필요한 테스트 사용자도 등록한다. Authorized redirect URI:

```text
https://auth.example.com/realms/ai-signal/broker/google/endpoint
```

realm/terraform.tfvars의 enable_google=true, google_client_id를 설정하고 `TF_VAR_google_client_secret`을 숨김 입력으로 설정한다. realm plan/apply를 수행한다. Google 로그인이 Keycloak 화면에 나타나면 실제 계정으로 로그인하고 role_required → 역할 부여 → 정상 접속 순서를 확인한다.

## 9. 네이버 연결

네이버 개발자센터에서 네이버 로그인 애플리케이션을 등록한다. 서비스 URL과 Callback URL을 설정한다. Callback:

```text
https://auth.example.com/realms/ai-signal/broker/naver/endpoint
```

enable_naver=true, naver_client_id와 `TF_VAR_naver_client_secret`을 설정하고 realm plan/apply한다. 이 코드는 공식 OIDC 메타데이터에 따라 `/oauth2/authorize`, `/oauth2/token`, RS256 JWKS, `openid profile`, client_secret_post, PKCE S256을 사용한다. 기존 OAuth2의 `/oauth2.0/*` 경로와 혼동하지 않는다.

Naver UserInfo는 중첩된 프로필 응답을 제공하므로 첫 버전은 disable_user_info=true로 ID token 기반 식별만 사용한다. 이름·이메일이 없으면 Keycloak 최초 프로필 확인 화면에서 보완할 수 있다. 이메일·추가 프로필 자동 매핑은 실제 동의/클레임 확인 후 확장한다. 앱 식별자는 이메일이 아닌 Keycloak sub다. 일반 사용자에게 오픈하려면 네이버 검수 및 개인정보 처리방침·동의 항목을 확인한다. 실제 발급 토큰을 이용한 종단 테스트는 사용자 설치 후 수행한다.

## 10. 로컬 앱 개발

```bash
cp .dev.vars.page-manager.example .dev.vars.page-manager
# origin/issuer/client secret을 로컬 파일에 설정
npm run build:pages
npm run db:pages:migrate
npm run dev:pages:api
# 다른 터미널
npm run dev:pages:web
```

접속은 `http://127.0.0.1:5174`로 통일한다. realm local_app_origin에도 같은 값을 넣어 콜백을 허용한다. 개발 종료 후 운영 realm에서는 local_app_origin을 제거한다. 로컬 Secret 파일은 커밋하지 않는다. EC2 Keycloak에 접근하므로 로컬 개발에서도 IdP가 실행 중이어야 한다.

## 11. 운영·백업·복구·업데이트

- EC2/EBS/공인 IPv4/DNS/스냅샷/트래픽 비용이 발생한다. 무료를 보장하지 않는다. AWS Budgets와 Cloudflare 사용량 알림을 설정한다. NAT/ALB/RDS는 이 코드에서 생성하지 않는다.
- Keycloak 준비 상태·TLS 만료·디스크 사용량을 확인한다. EC2 4GB 메모리를 기본으로 하며 사용량에 따라 증설한다. 2GB는 메모리 제한과 부하 검증을 거친 개인 실험용으로만 고려한다.
- DB 백업: SSM으로 접속해 `sudo sh -c 'umask 077; docker compose --project-directory /srv/keycloak exec -T postgres pg_dump -U keycloak -d keycloak > /srv/keycloak/backup.sql'` 실행. 파일을 암호화된 외부 저장소에 보관한다. 백업에는 사용자·인증 설정이 들어 있다.
- EBS 스냅샷은 DB 쓰기를 정지하거나 일관성 확보 후 생성한다. 같은 EBS 안 백업만으로 장애 복구를 보장하지 않는다. 복구 연습을 별도 인스턴스/DB에서 수행한다.
- 컨테이너 버전 변경 전 DB dump·EBS snapshot을 확보한다. Keycloak 스키마 업그레이드 후 이미지 태그만 낮추는 롤백은 안전하지 않다. 호환 이미지와 이전 DB 백업을 함께 복구한다.
- user-data 변경은 인스턴스 교체를 유발한다. EBS 재연결과 서비스 재시작 중 인증 중단이 있다. AMI 데이터 소스가 최신 이미지를 선택하므로 후속 plan에서 교체 여부를 항상 확인한다.
- 비밀번호 변경은 SSM 값 변경만으로 기존 PostgreSQL 계정에 반영되지 않는다. DB ALTER ROLE, 런타임 .env, 서비스 재시작을 일치시킨다. client secret 회전은 Keycloak과 Worker를 함께 갱신한다.
- 앱 즉시 권한 철회가 필요하면 사용자 sub를 확인하고 D1 sessions에서 해당 subject 레코드를 삭제한다. 기존 페이지 본문은 유지된다.
- 앱 `/auth/login`은 D1 쓰기를 발생시킨다. 외부 오픈 전 Cloudflare의 사용 가능한 rate limiting 정책을 설정하고 예산을 감시한다.
- Terraform destroy는 EBS prevent_destroy 때문에 차단된다. 백업·복구 검증 후 데이터 삭제 여부를 별도로 결정한다. EC2를 멈춰도 EBS/EIP 비용은 남을 수 있다.

## 12. 검증 체크리스트

- [ ] DNS/TLS 및 issuer 정확히 일치
- [ ] 공개 /admin/·/realms/master/ 404, EC2 8080 외부 접근 불가
- [ ] SSM 포워딩으로만 관리자 접속
- [ ] 앱 로그인, 정상 nonce/state/PKCE 처리
- [ ] 미로그인 401, 역할 없음 403, viewer 쓰기 403
- [ ] editor 다른 사용자 초안 조회/수정 차단
- [ ] Google·네이버 각각 첫 로그인과 재로그인
- [ ] 초안/공유 전환 및 동시 수정 충돌
- [ ] 세션 만료·앱 로그아웃·즉시 철회 SQL 절차
- [ ] 백업·복원 및 재부팅 후 DB 보존

## 공식 근거

- Keycloak 컨테이너: https://www.keycloak.org/server/containers
- Keycloak hostname: https://www.keycloak.org/server/hostname
- Keycloak reverse proxy: https://www.keycloak.org/server/reverseproxy
- Terraform provider: https://registry.terraform.io/providers/keycloak/keycloak/latest/docs
- Google OIDC: https://developers.google.com/identity/openid-connect/openid-connect
- 네이버 OIDC: https://developers.naver.com/docs/login/devguide/devguide.md
- 네이버 discovery: https://nid.naver.com/.well-known/openid-configuration
- AWS SSM: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html

- EC2 T3 사양/credit 설명: https://aws.amazon.com/ec2/instance-types/t3/
