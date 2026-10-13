# AI SIGNAL Keycloak on EC2

AI SIGNAL Research Desk의 인증 인프라. Keycloak·PostgreSQL·Caddy를 EC2 한 대에 설치하고, Google/네이버 OIDC 및 앱 역할을 구성한다. 제품은 Keycloak이며 저장소 이름 terraform-keyclock은 요청한 주소를 유지한다.

**사용자가 직접 설치하는 코드다. 자동 apply·AWS 배포는 하지 않는다.**

## 시작 순서

1. [관리자 설치 가이드](docs/ADMIN_GUIDE.md)의 준비물과 비용/state 항목을 읽는다.
2. SSM SecureString에 bootstrap 비밀번호를 준비한다.
3. `infra/ec2`에서 tfvars 작성 → init → plan → apply.
4. DNS를 EIP로 연결하고 TLS와 SSM 포트 포워딩을 확인한다.
5. `realm`에서 tfvars/비밀 환경 변수 작성 → init → plan → apply.
6. AI-News-Crawler의 Research Desk Worker를 별도 배포하고 계정 역할을 부여한다.
7. Google/네이버 IdP를 선택적으로 활성화하고 실제 로그인 검증.

## 구성

- 기본: t3.medium(2 vCPU/4GiB), Amazon Linux 2023 x86_64, 암호화 EBS DB 20GB + root 16GB.
- 네트워크: 신규 VPC 또는 `existing_network`로 기존 퍼블릭 서브넷 재사용.
- 외부 포트: 80/443. 관리자 8080은 localhost + SSM, PostgreSQL 포트 외부 미공개.
- T3 CPU credits: standard. Unlimited CPU credit 추가 과금 대신 credit 소진 시 성능 제한.
- DB volume: prevent_destroy. 실수로 데이터 삭제하지 않도록 destroy가 차단될 수 있다.
- 별도 상태: EC2와 realm 두 디렉터리를 순서대로 실행한다. realm state는 비밀을 포함하므로 비공개 관리.

## 문서

- [기획서](docs/PRODUCT_PLAN.md)
- [아키텍처](docs/ARCHITECTURE.md)
- [스택·구조](docs/STACK_STRUCTURE.md)
- [관리자 설치·운영](docs/ADMIN_GUIDE.md)
- [사용자 구성·사용](docs/USER_GUIDE.md)
- [검증 범위](docs/VALIDATION.md)

GitHub Actions는 fmt/validate/mock plan만 수행하며 AWS 자격 증명이 필요 없다. 실제 운영 가용성·소셜 로그인·복구는 설치 후 검증한다.
