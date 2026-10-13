# AI SIGNAL Research Desk 문서

1. [기획서](PRODUCT_PLAN.md): 뉴스 → 실습 → 브리핑으로 이어지는 기능과 후속 아이디어
2. [아키텍처](ARCHITECTURE.md): Cloudflare 앱 / EC2 Keycloak, 인증·인가·데이터 경계
3. [스택·구조](STACK_STRUCTURE.md): 파일 배치, API, 환경 변수 계약
4. [관리자 가이드](ADMIN_GUIDE.md): Terraform부터 소셜 로그인·배포·백업까지 직접 설치 절차
5. [사용자 가이드](USER_GUIDE.md): 계정·역할·페이지 작성과 오류 대응
6. [검증 기록](VALIDATION.md): 실행한 검증과 아직 수행하지 않은 운영 검증

실제 설치 전 관리자 가이드의 준비물, 비용, 비밀/state 관리 항목을 읽는다. IaC의 EC2/realm은 두 단계로 각각 apply한다. 실제 클라우드 배포를 수행한 문서가 아니다.
