# refresh-token-expiration-context.md

- status: validated
- updated_at: 2026-06-07 Asia/Seoul

## 배경
- prod와 dev 서버리스 백엔드의 refresh token 유효 기간을 기존 14일에서 2달로 늘린다.

## 범위
- `JWT_REFRESH_EXPIRATION` 환경변수만 변경한다.
- 적용 대상은 prod와 dev API 역할의 develop-shadow다.
- access token 만료, cleanup schedule, 백엔드 코드, 스크래핑 인프라는 변경하지 않는다.

## As-Is
- `tfvars/prod.tfvars`의 `JWT_REFRESH_EXPIRATION`은 `1209600000`ms다.
- `tfvars/develop-shadow.tfvars`와 `tfvars/develop-shadow.tfvars.example`의 `JWT_REFRESH_EXPIRATION`은 `1209600000`ms다.
- `tfvars/prod.tfvars.example`에는 prod JWT 민감값 주입을 실제 tfvars에서만 관리한다는 주석만 있다.

## To-Be
- prod와 develop-shadow의 `JWT_REFRESH_EXPIRATION`을 60일 기준 `5184000000`ms로 변경한다.
- 추적되는 example 파일에도 같은 refresh token 기간 기준을 남긴다.

## 구현 계획
- ignored 실제 tfvars인 `tfvars/prod.tfvars`, `tfvars/develop-shadow.tfvars`를 갱신한다.
- 추적되는 `tfvars/develop-shadow.tfvars.example`, `tfvars/prod.tfvars.example`를 갱신한다.
- Terraform 포맷과 validate를 실행한다.

## 실행 로그
- 2026-06-07 KST: `git fetch origin develop` 실행 후 `develop`이 behind-only임을 확인했다.
- 2026-06-07 KST: `git merge --ff-only origin/develop`로 로컬 `develop`을 최신화했다.
- 2026-06-07 KST: `tfvars/prod.tfvars`, `tfvars/develop-shadow.tfvars`, `tfvars/prod.tfvars.example`, `tfvars/develop-shadow.tfvars.example`의 refresh token 만료 기준을 `5184000000`ms로 변경했다.
- 2026-06-07 KST: `terraform fmt -recursive`를 실행했다.
- 2026-06-07 KST: sandbox 안의 첫 `terraform validate`는 AWS provider plugin schema handshake 실패로 중단됐다.
- 2026-06-07 KST: 동일 명령을 정상 권한으로 재실행했고 `Success! The configuration is valid.`를 확인했다.
- 2026-06-07 KST: `git diff --check`로 whitespace 오류가 없음을 확인했다.
- 2026-06-07 KST: `rg -n "JWT_REFRESH_EXPIRATION" tfvars/prod.tfvars tfvars/develop-shadow.tfvars tfvars/prod.tfvars.example tfvars/develop-shadow.tfvars.example`로 네 파일 모두 `5184000000` 값을 확인했다.

## 검증 결과
- `terraform fmt -recursive`: 통과
- `terraform validate`: 통과
- `git diff --check`: 통과
- `rg -n "JWT_REFRESH_EXPIRATION" ...`: prod/develop-shadow 실제 tfvars와 example 모두 `5184000000` 확인

## 전환 계획
- 변경된 prod/develop-shadow tfvars로 Terraform plan을 확인한 뒤 apply하면 Lambda 환경변수 변경으로 반영된다.

## 롤백 계획
- `JWT_REFRESH_EXPIRATION` 값을 기존 `1209600000`ms로 되돌리고 Terraform plan/apply를 수행한다.

## 오픈 이슈
- 실제 운영 반영 여부는 Terraform plan/apply 실행 여부에 따라 결정된다.
- prod/develop-shadow plan은 민감 Lambda 환경변수 출력 가능성이 있어 이번 검증에서는 실행하지 않았다.
