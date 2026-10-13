# 구현·검증 기록

기준일: 2026-10-13.

## 실행한 검증

- 기존 AI SIGNAL + Research Desk TypeScript 검사 통과.
- Vitest 54개 통과: 기존 회귀 47개 + 새 페이지 관리 7개.
- 새 테스트: 로그인/역할/만료 차단, CSRF, 초안 가시성, 소유권, 공유, 동시 수정 version, 관리자 삭제, 앱 로그아웃, 잘못된 callback, RS256 서명 토큰의 issuer/audience/nonce/만료 검증.
- 기존 뉴스 앱과 Research Desk Vite 빌드 통과.
- 새 Worker Wrangler deploy --dry-run 통과. 실제 업로드 없음.
- Keycloak provider 5.10.0과 AWS provider 6.68.0의 스키마 기반 validate 수행.
- Terraform mock plan 3개 통과: 신규 VPC, 기존 VPC 재사용, realm OIDC 계약. PKCE, role claim, 네이버 서명 검증, IMDSv2, 암호화 EBS, 공개 포트 제한을 검사. AWS/API에 연결하는 apply가 아니다.

## 미수행

- 실제 AWS plan/apply, cloud-init/Docker 부팅, DNS/TLS 발급, SSM 접속.
- 실제 Keycloak realm 적용 및 Google·네이버 인증. 토큰·소셜 클레임 호환성과 UI first broker login 흐름은 설치 후 확인해야 한다.
- 브라우저 E2E/시각 검증과 EC2 메모리·로그인 부하 측정.
- 자동 백업/복구 테스트, 실제 운영 rate limiting 설정.

## 의존성 검사

npm audit 전체 검사에서 기존 개발 테스트 체인의 vitest/@vitest/mocker/tinypool 관련 3건(critical 2, moderate 1)을 확인했다. 검증 당시 직접 추가한 jose에 대한 advisory는 없었다. 개발 체인 메이저 버전 업그레이드는 기존 변경과 분리할 필요가 있어 이 작업에서 자동 강제 업그레이드하지 않았다. 테스트 서버를 외부에 공개하지 않는다. 배포 전 업데이트 계획을 잡는다.

## 적용 경계

앱 코드는 기존 AI-News-Crawler 작업 트리의 다른 미커밋 변경을 보존한 채 추가했다. 앱은 로컬 구현이며 기존 배포 workflow에 자동 편입하지 않았다. IaC만 지정된 별도 저장소의 feature 브랜치/PR 대상으로 준비한다. 비밀, tfvars, state, plan, .terraform 디렉터리는 PR에서 제외한다.
