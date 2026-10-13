# 스택·코드 구조·설정 계약

| 구분 | 선택 |
|---|---|
| UI | 기존 React 19 / TypeScript / Vite, 전용 CSS |
| BFF/API | Hono, Cloudflare Workers Static Assets |
| 검증 | Zod, jose 6.1.3 JWT 검증 |
| 저장 | 별도 D1, auth_flows / sessions / pages |
| IdP | Keycloak 26.8.0, Google OIDC, 네이버 OIDC |
| EC2 | Amazon Linux 2023 x86_64, Docker Compose 2.39.4 |
| DB/TLS | PostgreSQL 17.6, Caddy 2.10.2 |
| IaC | Terraform >=1.7, AWS provider 6.x(lock 고정), Keycloak provider 5.10.0 |

컨테이너는 버전 태그를 고정했지만 digest 고정은 아니다. 업데이트 전 릴리스/보안 공지와 백업·복구 절차를 확인한다. 테스트한 Terraform CLI는 1.13.4다.

```text
AI-News-Crawler/
  apps/page-manager/src/          화면
  apps/page-manager/public/       정적 응답 보안 헤더
  packages/page-manager/model.ts  입력 계약·역할
  workers/page-manager/auth.ts    PKCE·JWT 검증
  workers/page-manager/index.ts   BFF·인가·페이지 API
  migrations-page-manager/       기존 뉴스와 분리된 DB 스키마
  wrangler.page-manager.jsonc     별도 Worker 및 D1
  vite.page-manager.config.ts     별도 빌드
  tests/page-manager.test.ts      로컬 D1·권한·OIDC 검증
  docs/page-manager/              설계·설치·사용 문서
terraform-keyclock/
  infra/ec2/                     AWS 인프라와 부팅 템플릿
  realm/                         실행 중 Keycloak realm/client/IdP/roles
  docs/                          양쪽 설치·운영 문서 사본
  .github/workflows/validate.yml  검증만 수행, apply 없음
```

## 앱 설정

| 변수 | 설명 |
|---|---|
| APP_ORIGIN | 앱의 정확한 origin, 마지막 슬래시 없음 |
| OIDC_ISSUER | `https://auth.example.com/realms/ai-signal` |
| OIDC_CLIENT_ID | `page-manager` |
| OIDC_CLIENT_SECRET | Keycloak app_client_secret과 동일, Wrangler secret |
| ALLOW_LOCAL_HTTP | 로컬 개발에서만 true; localhost/127.0.0.1만 허용 |
| NEWS_API_ORIGIN | 기존 뉴스 API HTTPS origin; 브라우저 입력 URL로 교체 불가 |

`VITE_*`에 secret을 넣지 않는다. 앱 콜백은 APP_ORIGIN/auth/callback, 소셜 콜백은 Keycloak broker endpoint다.

## API

| 메서드/경로 | 동작 |
|---|---|
| GET /auth/login | Keycloak으로 이동 |
| GET /auth/callback | 코드 교환·세션 생성 |
| GET /api/me | 사용자·역할 |
| POST /api/logout | 앱 세션 폐기 |
| GET /api/pages | 접근 가능한 최근 100개 |
| POST /api/pages | editor/admin 작성 |
| PUT /api/pages/:id | owner-editor/admin 수정, version 필수 |
| DELETE /api/pages/:id?version=N | admin 삭제, 버전 일치 필수 |
| GET /api/news | 기존 AI SIGNAL 최근 12건 조회 |

페이지 입력: title, body, tags 배열, sources[{title,url}], stage(read/practice/summarize), status(draft/shared), 수정 시 version. 본문은 일반 텍스트이며 HTML을 실행하지 않는다. 저장소 접근은 파라미터 SQL을 사용한다. 기존 뉴스의 Swagger에는 이 별도 앱 API를 혼합하지 않았다.
