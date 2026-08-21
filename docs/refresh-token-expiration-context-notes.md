# refresh token expiration context notes

- 2026-06-07 KST: 로컬 `develop`은 `origin/develop`보다 17커밋 뒤처져 있었고, 작업 전 fast-forward했다.
- 2026-06-07 KST: 실제 서버리스 dev API는 `tfvars/develop-shadow.tfvars`의 `SPRING_PROFILES_ACTIVE=develop-shadow`, `custom_domain_name=dev.api.cchaksa.com` 기준으로 관리된다.
- 2026-06-07 KST: prod와 develop-shadow의 현재 `JWT_REFRESH_EXPIRATION`은 `1209600000`ms이며, 이는 14일이다.
- 2026-06-07 KST: 백엔드 환경변수는 밀리초 문자열 기준으로 관리되므로 2달은 60일 기준 `5184000000`ms로 반영한다.
- 2026-06-07 KST: `tfvars/prod.tfvars`, `tfvars/develop-shadow.tfvars`는 `.gitignore` 대상이라 실제 값은 로컬 적용용이고, Git diff에는 example과 context 문서만 나타난다.
- 2026-06-07 KST: 민감값 노출을 피하기 위해 prod/develop-shadow plan은 실행하지 않고 `terraform validate`와 값 검색으로 검증했다.
