# lambda-health-diskspace-context.md

상태: done

## 배경

2026-05-11 prod Lambda 배포 후 `GET /actuator/health`가 503을 반환했다. 같은 경로를 develop-shadow에서도 확인한 결과 동일하게 `diskSpace` health가 `/var/task/.`를 검사하고 `free=0`으로 판단해 전체 health가 `DOWN`이 되었다.

## 범위

- develop-shadow Lambda에 먼저 diskSpace health 비활성화 환경변수를 적용한다.
- develop-shadow 검증이 통과하면 prod Lambda에도 동일 환경변수를 적용한다.
- Route53/DNS 전환, 기존 EC2/ALB/ASG 변경, scheduler 활성화는 포함하지 않는다.

## As-Is

- develop-shadow `live` alias: version 59.
- prod `live` alias: version 5.
- 두 Lambda 모두 `MANAGEMENT_HEALTH_DISKSPACE_ENABLED`, `MANAGEMENT_HEALTH_DISKSPACE_PATH`가 없다.
- `GET /actuator/health` 결과는 DB `UP`, diskSpace `DOWN`, HTTP 503이다.
- `GET /v3/api-docs`는 develop-shadow/prod 모두 HTTP 200으로 응답해 애플리케이션 라우팅 자체는 정상이다.

## To-Be

- Lambda 환경에서는 Actuator diskSpace health를 비활성화한다.
- 환경변수: `MANAGEMENT_HEALTH_DISKSPACE_ENABLED=false`.
- `GET /actuator/health`가 DB 등 실제 애플리케이션 상태 기준으로 HTTP 200/UP을 반환해야 한다.

## 구현 계획

1. `tfvars/develop-shadow.tfvars`와 example에 `MANAGEMENT_HEALTH_DISKSPACE_ENABLED=false` 추가.
2. develop-shadow backend state로 Terraform reconfigure.
3. develop-shadow plan/apply 후 `/actuator/health`, `/v3/api-docs` 확인.
4. 문제가 없으면 prod tfvars/example에도 동일 값 추가.
5. prod backend state로 Terraform reconfigure 후 plan/apply.
6. prod `/actuator/health`, `/v3/api-docs`, post-apply plan 확인.

## 실행 로그

- 2026-05-11 KST: 작업 시작.

## 검증 결과

- 최종 검증 결과는 아래 `검증 결과 추가` 섹션들에 누적 기록했다.

## 전환 계획

- Lambda health endpoint가 정상화되면 prod health check/모니터링 기준에 사용할 수 있다.
- 기존 EC2 prod 트래픽 전환은 별도 승인 후 진행한다.

## 롤백 계획

- `MANAGEMENT_HEALTH_DISKSPACE_ENABLED` env를 제거하거나 `true`로 되돌리고 Terraform apply 한다.
- 문제가 생기면 Lambda alias를 이전 정상 version으로 되돌린다.

## 오픈 이슈

- 없음.

## 실행 로그 추가

- 2026-05-11 KST: develop-shadow 실제 `tfvars/develop-shadow.tfvars`와 `tfvars/develop-shadow.tfvars.example`에 `MANAGEMENT_HEALTH_DISKSPACE_ENABLED=false`를 추가했다.
- 2026-05-11 KST: `terraform init -reconfigure -backend-config=backend/backend-develop-shadow.hcl`로 develop-shadow state에 연결했다.
- 2026-05-11 KST: `terraform plan -var-file=tfvars/develop-shadow.tfvars -out=/tmp/develop-shadow-diskspace.tfplan` 결과 변경 대상은 `module.backend_serverless[0].aws_lambda_function.backend` 1개뿐이었다.
- 2026-05-11 KST: `terraform apply -auto-approve /tmp/develop-shadow-diskspace.tfplan` 결과 `0 added, 1 changed, 0 destroyed`.
- 2026-05-11 KST: Terraform apply로 생성된 develop-shadow Lambda version `60`은 `Active`, `LastUpdateStatus=Successful`, `MANAGEMENT_HEALTH_DISKSPACE_ENABLED=false`를 포함했다.
- 2026-05-11 KST: `live` alias는 lifecycle ignore 정책 때문에 기존 version `59`에 남아 있어, AWS CLI로 `live -> 60` alias를 갱신했다.

## 검증 결과 추가

- 2026-05-11 KST develop-shadow `GET /actuator/health`: HTTP 200, 전체 `UP`, DB `UP`, ping `UP`.
- 2026-05-11 KST develop-shadow `GET /v3/api-docs`: HTTP 200.

## 실행 로그 추가 2

- 2026-05-11 KST: develop-shadow 검증 통과 후 prod 실제 `tfvars/prod.tfvars`와 `tfvars/prod.tfvars.example`에 `MANAGEMENT_HEALTH_DISKSPACE_ENABLED=false`를 추가했다.
- 2026-05-11 KST: `terraform init -reconfigure -backend-config=backend/backend-prod.hcl`로 prod state에 연결했다.
- 2026-05-11 KST: `terraform plan -var-file=tfvars/prod.tfvars -out=/tmp/prod-diskspace.tfplan` 결과 변경 대상은 `module.backend_serverless[0].aws_lambda_function.backend` 1개뿐이었다.
- 2026-05-11 KST: `terraform apply -auto-approve /tmp/prod-diskspace.tfplan` 결과 `0 added, 1 changed, 0 destroyed`.
- 2026-05-11 KST: Terraform apply로 생성된 prod Lambda version `6`은 `Active`, `LastUpdateStatus=Successful`, `MANAGEMENT_HEALTH_DISKSPACE_ENABLED=false`를 포함했다.
- 2026-05-11 KST: `live` alias는 lifecycle ignore 정책 때문에 기존 version `5`에 남아 있어, AWS CLI로 `live -> 6` alias를 갱신했다.

## 검증 결과 추가 2

- 2026-05-11 KST prod `GET /actuator/health`: HTTP 200, 전체 `UP`, DB `UP`, ping `UP`.
- 2026-05-11 KST prod `GET /v3/api-docs`: HTTP 200.

## 정정

- 초기 To-Be에는 Lambda health endpoint가 200/UP을 반환해야 한다고만 기록했으나, 실제 적용 시 Terraform의 `aws_lambda_alias.live.function_version`은 lifecycle ignore 대상이므로 Lambda env 변경 후 API Gateway 경로에 즉시 반영하려면 별도 alias 갱신 또는 백엔드 배포 workflow의 alias 갱신이 필요하다.

## 검증 결과 추가 3

- 2026-05-11 KST prod post-apply `terraform plan -var-file=tfvars/prod.tfvars -out=/tmp/prod-diskspace-post.tfplan`: 변경 0개.
- 2026-05-11 KST `terraform fmt -check`: 통과.
- 2026-05-11 KST `terraform validate`: sandbox 내부 provider schema 로드 실패 후 제한 밖 재실행으로 통과.
