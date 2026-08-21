# eventbridge-maintenance-scheduler-context.md

- status: in-progress
- updated_at: 2026-04-26 Asia/Seoul

## 배경
- 백엔드가 Lambda 기반으로 전환되면서 애플리케이션 내부 `@Scheduled` 작업을 안정적으로 실행하기 어렵다.
- 오래 `RUNNING` 상태에 머문 scrape job 정리와 만료 refresh token cleanup은 외부 durable trigger가 실행하는 구조가 더 적합하다.

## 변경 내용
- `modules/backend_serverless`에 `maintenance_schedules` 입력을 추가한다.
- 활성화 시 EventBridge Scheduler schedule 2개를 생성한다.
  - `SCRAPE_JOB_RECONCILE_STALE`: `rate(1 minute)`
  - `REFRESH_TOKEN_CLEANUP`: `rate(1 hour)`
- 백엔드 maintenance handler 배포 후 Scheduler state를 `ENABLED`로 전환했다.
- Scheduler target은 API Gateway가 아니라 backend Lambda `live` alias를 직접 invoke한다.
- Scheduler execution role은 backend Lambda alias invoke와 Scheduler DLQ `sqs:SendMessage`만 허용한다.
- Lambda resource policy는 schedule별 `source_arn`으로 invoke permission을 제한한다.
- Scheduler payload의 `scheduled_at`은 EventBridge Scheduler context attribute `<aws.scheduler.scheduled-time>`을 사용한다.
- Lambda 환경변수에는 `SCRAPING_SCHEDULER_ENABLED=false`를 명시한다.
- develop-shadow 원격 state에 이미 존재하는 scrape result S3 리소스가 현재 브랜치에서 삭제 계획으로 잡히지 않도록 `scrape_result_storage` 정의와 backend/worker 환경변수 주입도 함께 복원한다.

## 검증 기준
- `terraform fmt -recursive`
- `terraform validate`
- `terraform plan -var-file=tfvars/develop-shadow.tfvars`
- plan에서 Scheduler 2개, Scheduler IAM role/policy, Scheduler DLQ, Lambda permission 2개가 추가되고 Scheduler state가 `ENABLED`인지 확인한다.
- plan에서 scrape result S3 bucket/정책 삭제, worker task definition 교체, Lambda memory/reserved concurrency 되돌림이 발생하지 않는지 확인한다.
- Lambda 환경변수에 `SCRAPING_SCHEDULER_ENABLED=false`가 유지되는지 확인한다.

## 롤백
- `backend_serverless.maintenance_schedules.enabled=false`로 되돌리고 Terraform apply 한다.
- Scheduler, Scheduler role/policy, Scheduler DLQ, Scheduler invoke permission이 제거되는지 plan으로 확인한다.
