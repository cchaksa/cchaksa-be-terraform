# refresh token expiration checklist

- [x] 최신 `origin/develop` 기준으로 로컬 `develop` fast-forward
- [x] prod/develop-shadow refresh token 환경변수 위치 확인
- [x] prod/develop-shadow refresh token 만료 값을 60일로 변경
- [x] 추적되는 tfvars example에 동일 기준 반영
- [x] `terraform fmt` 실행
- [x] `terraform validate` 실행
- [x] 변경 범위와 남은 리스크 정리
