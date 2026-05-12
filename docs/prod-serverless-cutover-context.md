# prod-serverless-cutover-context

상태: cutover

## 배경
- prod 백엔드 서버리스 병행 리소스 준비와 Lambda 배포 검증이 완료되었다.
- `api.cchaksa.com` DNS를 기존 ALB에서 API Gateway custom domain으로 전환하고, Lambda maintenance 작업을 EventBridge Scheduler로 실행해야 한다.

## 범위
- prod API DNS 전환 상태 확인.
- prod EventBridge Scheduler 활성화.
- Scheduler가 Backend Lambda `live` alias를 직접 호출하는지 검증.
- 기존 EC2/ALB 제거는 이번 범위에 포함하지 않는다.

## As-Is
- `api.cchaksa.com`은 기존 prod ALB를 바라보던 운영 API 도메인이었다.
- prod EventBridge Scheduler 리소스는 생성되어 있었지만 `DISABLED` 상태였다.
- Scheduler target은 `arn:aws:lambda:ap-northeast-2:984762359128:function:prod-haksa-api:live`로 구성되어 있었다.

## To-Be
- `api.cchaksa.com`은 API Gateway custom domain target `d-dom0cpkh9d.execute-api.ap-northeast-2.amazonaws.com`을 바라본다.
- prod maintenance scheduler 2개를 `ENABLED` 상태로 전환한다.
- stale scrape job reconcile은 `rate(5 minutes)`, refresh token cleanup은 `rate(1 hour)`로 실행한다.

## 구현 계획
- DNS 현재 해석값을 확인한다.
- `tfvars/prod.tfvars`와 `tfvars/prod.tfvars.example`의 `maintenance_schedules.state`를 `ENABLED`로 변경한다.
- `terraform plan -var-file=tfvars/prod.tfvars`로 변경 범위가 scheduler 활성화에 국한되는지 확인한다.
- `terraform apply -var-file=tfvars/prod.tfvars`를 실행한다.
- AWS Scheduler와 Lambda policy를 조회해 적용 결과를 검증한다.

## 체크리스트
- [x] DNS 현재 해석값 확인.
- [x] API Gateway custom domain health 확인.
- [x] prod scheduler 상태 변경 반영.
- [x] Terraform plan 확인.
- [x] Terraform apply 실행.
- [x] Scheduler 상태 검증.
- [x] Lambda invoke permission 검증.

## 실행 로그
- 2026-05-13 KST: `api.cchaksa.com`이 `d-dom0cpkh9d.execute-api.ap-northeast-2.amazonaws.com`으로 해석되는 것을 확인했다.
- 2026-05-13 KST: `https://api.cchaksa.com/health`가 API Gateway 응답 헤더 `apigw-requestid`와 함께 `200 ok`를 반환하는 것을 확인했다.
- 2026-05-13 KST: 일반 `terraform plan -var-file=tfvars/prod.tfvars`에서 Scheduler 활성화 외에 scraper worker task definition drift가 함께 감지되었다.
- 2026-05-13 KST: ECS task definition 교체를 피하기 위해 Scheduler 2개만 `-target`으로 제한해 plan/apply 했다.
- 2026-05-13 KST: targeted apply 결과 `0 added, 2 changed, 0 destroyed`로 완료되었다.
- 2026-05-13 KST: 동일 target 범위 재실행 plan 결과 `No changes`를 확인했다.

## 검증 결과
- `prod-haksa-api-scrape-job-stale-reconcile`
  - 상태: `ENABLED`
  - 주기: `rate(5 minutes)`
  - 대상: `arn:aws:lambda:ap-northeast-2:984762359128:function:prod-haksa-api:live`
  - payload task: `SCRAPE_JOB_RECONCILE_STALE`
- `prod-haksa-api-refresh-token-cleanup`
  - 상태: `ENABLED`
  - 주기: `rate(1 hour)`
  - 대상: `arn:aws:lambda:ap-northeast-2:984762359128:function:prod-haksa-api:live`
  - payload task: `REFRESH_TOKEN_CLEANUP`
- Lambda `prod-haksa-api:live` policy에 아래 Scheduler invoke permission이 존재한다.
  - `AllowSchedulerInvoke-scrape_job_reconcile_stale`
  - `AllowSchedulerInvoke-refresh_token_cleanup`
- Scheduler DLQ `prod-haksa-api-maintenance-scheduler-dlq`의 즉시 적재 메시지는 0건이다.
- targeted Terraform plan 기준 Scheduler 2개는 현재 설정과 실제 인프라가 일치한다.

## 전환 계획
- Scheduler 활성화 후 CloudWatch Logs와 Scheduler DLQ를 확인한다.
- prod API 트래픽은 `api.cchaksa.com` 기준으로 Lambda/API Gateway를 통과한다.

## 롤백 계획
- DNS 롤백은 Cloudflare에서 `api.cchaksa.com`을 기존 ALB `prod-alb-2085068023.ap-northeast-2.elb.amazonaws.com`으로 되돌린다.
- Scheduler 롤백은 `maintenance_schedules.state = "DISABLED"`로 되돌린 뒤 `terraform apply -var-file=tfvars/prod.tfvars`를 실행한다.

## 오픈 이슈
- 기존 EC2/ALB/ASG 제거는 별도 승인 후 진행한다.
- 일반 Terraform plan에 scraper worker task definition drift가 남아 있다. 전체 apply 전 별도 검토가 필요하다.
