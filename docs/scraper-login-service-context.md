# 동기 스크래퍼 로그인 서비스 Context

- 상태: validated

## 배경
2026-09-07 develop-shadow `/portal/login`은 삭제된 ALB DNS로 인해 실패했다.

## 범위
동기 `/login` ECS Service를 API Gateway HTTPS와 VPC Link 뒤에 생성한다. `/portal/link` 비동기 경로는 변경하지 않는다.

## As-Is
Backend Lambda가 존재하지 않는 공개 ALB를 호출한다.

## To-Be
Backend Lambda가 `https://dev.api.cchaksa.com/internal/scraper/login`을 호출하고, API Gateway가 내부 ALB와 ECS Service로 전달한다. 공유 secret header로 내부 호출을 검증한다.

## 구현 계획
IaC 생성, scraper와 BE 계약 변경, develop-shadow plan/apply, health와 로그인 호출을 검증한다.

## 실행 로그
2026-09-07 scraper ECS Service, scraper Lambda/API Gateway가 없음을 확인했다.

## 검증 결과
2026-09-07 develop-shadow에서 Terraform apply `12 added, 1 changed, 0 destroyed`를 확인했다. ECS Service는 desired/running `1/1`, rollout `COMPLETED`다. 무인증 내부 route는 403, 인증 header를 포함한 잘못된 포털 계정은 401을 반환해 실제 포털 검증까지 도달함을 확인했다.

## 전환 계획
develop-shadow에만 적용한다.

## 롤백 계획
route/service를 비활성화하고 Lambda 환경변수를 이전 값으로 복원한다.

## 오픈 이슈
prod는 이번 범위에서 제외한다.
