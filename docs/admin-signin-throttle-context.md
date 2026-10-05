# dev 관리자 로그인 API throttle 컨텍스트

- 상태: `done`
- 이슈: `#36`
- 환경: `develop-shadow`

## 배경

dev 관리자 인증은 로컬 `loginId`와 password 로그인을 사용한다. 반복 로그인 요청이 기존 `$default` route를 통해 제한 없이 Lambda로 전달되므로, 다른 API route를 변경하지 않고 로그인 경로만 API Gateway HTTP API에서 제한한다.

## 범위

- 적용 state는 `backend/backend-develop-shadow.hcl`의 `terraform/develop-shadow/terraform.tfstate`다.
- `POST /api/admin/auth/signin` explicit route를 추가하고 기존 `aws_apigatewayv2_integration.lambda_proxy`를 재사용한다.
- `$default` stage의 해당 route에만 `throttling_rate_limit=1`, `throttling_burst_limit=5`를 설정한다.
- `$default` route와 다른 API route는 변경하지 않는다.
- 설정은 기본 비활성화이며 develop-shadow 실제 입력에서만 활성화한다. prod에는 적용하지 않는다.

## As-Is

- 관리자 로그인 요청은 `$default` route를 통해 기존 Lambda proxy integration으로 전달됐다.
- 로그인 경로만의 API Gateway throttle은 없었다.
- 기본 execute-api endpoint는 활성화 상태다.

## To-Be

- 관리자 로그인 요청은 같은 Lambda integration을 사용하는 explicit route로 전달된다.
- `$default` stage에서 이 route에만 rate `1 RPS`, burst `5`가 적용된다.
- `$default` route와 다른 API route는 그대로 유지된다.

## 구현 계획

- 실제 develop-shadow tfvars와 remote state를 사용한 non-target 전체 saved plan을 검토한다.
- 허용 변경은 explicit route `1 add`, `$default` stage route settings `1 change`, `0 destroy`뿐이다.
- 다른 주소의 변경 또는 삭제가 있으면 apply하지 않는다.
- apply 후 API Gateway route target이 기존 Lambda integration인지, stage route settings가 rate `1`과 burst `5`인지 AWS read-back한다.
- `$default` route와 기존 route 목록이 유지되는지 확인한다.

## 제한과 비용

- route throttle은 로그인 route 전체 요청을 합산하는 best-effort target이며 사용자 또는 IP별 hard limit이 아니다.
- 기본 execute-api endpoint가 활성화되어 있어 CloudFront/WAF 같은 edge 제어를 우회할 수 있다. 같은 API의 explicit route throttle 자체는 direct endpoint 요청에도 적용된다.
- route와 stage throttle 설정에는 별도 고정 비용이 없지만 기존 HTTP API request, data transfer와 Lambda 사용량 과금은 계속된다.
- 인증 실패 횟수 기반 잠금, 사용자/IP별 제한과 WAF rate-based rule은 별도 방어 계층으로 다룬다.

## 전환 계획

- develop-shadow 전체 plan이 허용 범위와 일치할 때 saved plan을 적용한다.
- 적용 직후 AWS API Gateway route, integration, stage를 read-back한다.
- post-apply 전체 plan이 `No changes`인지 확인한다.

## 롤백 계획

- `admin_signin_throttle.enabled=false`로 되돌린 non-target plan이 explicit route 삭제와 stage route settings 제거만 포함하는지 확인한 뒤 적용한다.
- `$default` route가 유지되므로 롤백 후 로그인 요청은 기존 Lambda integration으로 계속 전달된다.

## AGENTS.md 검토

- 모듈 구조, 브랜치 규칙, 운영 전환 기준은 바뀌지 않으므로 `AGENTS.md` 갱신은 필요하지 않다.

## 실행 로그

- 2026-10-02 develop-shadow: 실제 입력을 remote state의 현재 Lambda, ECS, Scheduler와 네트워크 설정으로 재구성하고 민감 로컬 tfvars로만 사용했다.
- 2026-10-02 develop-shadow: non-target 전체 saved plan은 `1 add / 1 change / 0 destroy`였다.
- 생성 주소는 `module.backend_serverless[0].aws_apigatewayv2_route.admin_signin[0]`, in-place 변경 주소는 `module.backend_serverless[0].aws_apigatewayv2_stage.default`뿐이었다.
- 2026-10-02 develop-shadow: saved plan 적용 결과는 `1 added / 1 changed / 0 destroyed`였다.

## 검증 결과

- AWS read-back에서 `$default`와 `POST /api/admin/auth/signin`이 같은 기존 Lambda proxy integration을 사용함을 확인했다.
- stage route settings에는 `POST /api/admin/auth/signin`의 rate `1`, burst `5`만 존재한다.
- 기본 execute-api endpoint는 활성화 상태이며 위에 기록한 edge 우회 제한이 남는다.
- 2026-10-02 develop-shadow: apply 후 non-target 전체 plan은 `No changes`다.
- `terraform validate`, `terraform fmt -check -recursive`, `git diff --check`는 모두 통과했다.

## 오픈 이슈

- 사용자/IP별 로그인 실패 잠금과 WAF rate-based rule은 별도 이슈로 다룬다.
- execute-api endpoint 비활성화 여부는 다른 직접 호출 의존성을 확인한 뒤 별도로 결정한다.

## prod 적용 준비

- prod 관리자 로그인 공개 전에 `admin_signin_throttle`을 rate `1 RPS`, burst `5`로 활성화한다.
- prod 전체 입력은 Git에 저장하지 않고 GitHub `prod` Environment의 `PROD_TFVARS` secret으로 주입한다.
- Plan workflow는 resource address와 action 개수만 Summary에 남기고 destroy/replace가 있으면 실패한다.
- Apply workflow는 `main` exact SHA, 검토한 add/change 개수, resource-change SHA-256 digest와 destroy/replace 0을 다시 검증한 뒤 재생성한 saved plan만 적용한다.
- 실제 prod 적용의 허용 변경은 `POST /api/admin/auth/signin` route 1개 추가와 `$default` stage route settings 1개 변경뿐이다.
- 적용 후 route가 기존 Lambda integration을 사용하고 rate `1`, burst `5`인지 AWS read-back하며 전체 post-apply plan이 `No changes`인지 확인한다.
