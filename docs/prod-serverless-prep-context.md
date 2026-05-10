# prod-serverless-prep-context.md

## 작업 목적

prod의 기존 EC2 + ASG + ALB 상시 운영 경로에 영향을 주지 않는 범위에서, develop-shadow에서 검증한 서버리스/비동기 병행 리소스를 prod에도 사전 생성할 수 있도록 Terraform 설정을 준비한다.

## 기준

- 현재 prod 트래픽 경로는 유지한다.
- Route53/DNS 전환은 이번 작업에 포함하지 않는다.
- 기존 `component` 모듈의 EC2/ASG/ALB 리소스는 유지한다.
- 신규 prod Lambda/API Gateway/SQS/ECS/S3/EventBridge Scheduler는 병행 리소스로 준비한다.
- maintenance scheduler는 리소스만 만들고 실행은 `DISABLED` 상태로 둔다.

## 변경 사항

### `main.tf`

- `scrape_result_storage`를 prod에서도 사용할 수 있도록 허용했다.
- 결과 저장 버킷 기본 prefix를 `develop-shadow/` 고정에서 `<environment>/` 기본값으로 변경했다.
- prod에서 `scrape_result_storage.enabled=true`이면 `cck-prod-scrape-results-<account_id>` 버킷과 prefix 범위 IAM/env 주입이 가능해진다.
- 신규 prod SQS queue ARN은 apply 전까지 unknown이므로, Lambda SQS env/IAM 생성 여부를 ARN 문자열 조건이 아니라 명시 boolean으로 제어하도록 `backend_serverless` 모듈 입력을 보강했다.

### `tfvars/prod.tfvars`

- prod 병행 서버리스 리소스 생성을 위해 아래 토글을 활성화했다.
  - `enable_scraper_async=true`
  - `enable_scraper_worker_infra=true`
  - `enable_backend_serverless=true`
- scraper worker는 EventBridge Pipe 입력 구조에 맞춰 `WORKER_INPUT_MODE=pipe`를 사용하도록 정리했다.
- 기존 `SQS_QUEUE_URL` 직접 poll 설정은 제거했다.
- callback base URL은 prod API 도메인 기준인 `https://api.cchaksa.com`으로 설정했다.
- backend Lambda 설정을 최신 `backend_serverless` 스키마에 맞게 추가했다.
  - app name: `haksa-api`
  - package: `../haksa/build/distributions/haksa-lambda.zip`
  - memory: `2048`
  - reserved concurrency: `100`
  - provisioned concurrency: `0`
  - maintenance schedules: `enabled=true`, `state=DISABLED`
  - Grafana Cloud: `enabled=false`
- prod EC2 `/home/ubuntu/env.sh`에서 운영 환경변수 키를 확인하고, Lambda prod profile에 실제로 필요한 키만 실제 `tfvars/prod.tfvars`에 반영했다.
  - 반영 대상: Apple/Kakao app key, crawler base URL, JWT, prod DB, prod Sentry, Lambda 전용 `LOG_PATH`, `SPRING_PROFILES_ACTIVE`, `SCRAPING_SCHEDULER_ENABLED`
  - 제외 대상: `DEV_*`, `LOCAL_*`, 현재 prod profile에서 사용하지 않는 Redis 관련 키
  - `SCRAPING_JOB_QUEUE_URL`, `SCRAPING_CALLBACK_HMAC_SECRET`, `SCRAPING_RESULT_*`는 모듈에서 자동 주입하므로 직접 중복 설정하지 않았다.
- 현재 Lambda package의 `application.yml`에 OTLP tracing endpoint 기본값이 빈 문자열인 상태가 있어, prod Lambda env에 `MANAGEMENT_OTLP_TRACING_ENDPOINT=http://localhost:4318/v1/traces`를 명시했다.
- prod 결과 저장소를 추가했다.
  - bucket name 자동 생성
  - prefix: `prod/`
  - timeout/max payload 값은 develop-shadow와 동일
- 실제 `tfvars/prod.tfvars`는 Git ignore 대상이므로, 민감값을 제거한 `tfvars/prod.tfvars.example`을 함께 추가했다.

### `AGENTS.md`

- 결과 저장 버킷 설명을 develop-shadow 전용에서 shadow/prod 승인 적용 구조로 갱신했다.
- 결과 저장 prefix 기본값을 `<environment>/`로 문서화했다.
- prod 접두어 기준과 운영 트래픽 전환 승인 조건을 명시했다.

## 의도적으로 하지 않은 일

- Route53 record 전환 없음
- 기존 EC2/ASG/ALB 제거 또는 수정 없음
- maintenance scheduler 실행 활성화 없음
- Provisioned Concurrency 설정 없음
- Grafana Cloud prod ingest token 연결 없음
- scraper worker 실제 sha 이미지 태그 고정 없음

## 검증 결과

- `terraform fmt -check`: 통과
- `terraform validate`: 통과
- `terraform plan -var-file=tfvars/prod.tfvars -out=/tmp/prod-serverless-prep.tfplan`: 통과
- plan 요약:
  - create: 45
  - read: 3
  - no-op: 31
  - update/delete: 0
- 기존 `module.component`의 EC2/ASG/ALB/VPC/SG/Launch Template/Listener 리소스는 모두 `no-op`임을 확인했다.
- maintenance scheduler 2개는 모두 `state=DISABLED`로 계획됨을 확인했다.
- 생성 대상은 병행 Lambda/API Gateway/SQS/ECS/S3/EventBridge Scheduler/IAM/LogGroup 중심이다.
- 사용자 승인 후 `terraform apply -auto-approve /tmp/prod-serverless-prep.tfplan` 실행:
  - `45 added, 0 changed, 0 destroyed`
- apply 후 `terraform plan -var-file=tfvars/prod.tfvars -out=/tmp/prod-serverless-prep-postapply.tfplan`: 변경 0개 확인
- AWS 상태 확인:
  - `prod-haksa-api-scrape-job-stale-reconcile`: `DISABLED`, `rate(5 minutes)`
  - `prod-haksa-api-refresh-token-cleanup`: `DISABLED`, `rate(1 hour)`
  - `prod-scraper-jobs`: visible 0, not visible 0
  - `prod-scraper-jobs-dlq`: visible 0, not visible 0
  - `prod-scraper-cluster`: RUNNING task 0
- prod Lambda 환경변수 반영:
  - EC2 env 기반 키를 실제 `tfvars/prod.tfvars`에 반영했으며 민감값은 문서와 example에 기록하지 않았다.
  - 1차 apply는 Lambda version `2` publish 중 SnapStart 초기화 실패로 provider waiter timeout이 발생했다.
  - CloudWatch 원인: `MANAGEMENT_OTLP_TRACING_ENDPOINT`가 빈 문자열로 해석되어 `Invalid endpoint, must start with http:// or https://` 발생.
  - OTLP endpoint env를 명시한 뒤 재적용했고, `terraform apply -auto-approve /tmp/prod-lambda-env-fix.tfplan` 결과 `0 added, 1 changed, 0 destroyed`.
  - apply 후 `terraform plan -var-file=tfvars/prod.tfvars -out=/tmp/prod-post-env.tfplan`: 변경 0개 확인.
  - Lambda version `3`: `Active`, `LastUpdateStatus=Successful`.
  - Lambda `live` alias는 기존 정책대로 Terraform에서 `function_version` drift를 ignore하므로 version `1` 유지. prod backend 배포 workflow가 이후 새 code/env 버전을 publish하고 alias를 갱신해야 한다.

## 생성된 주요 리소스

- Backend Lambda: `prod-haksa-api`
- Backend Lambda alias: `live`
- Backend API endpoint: `https://51xqikq1h5.execute-api.ap-northeast-2.amazonaws.com`
- API Gateway custom domain: `api.cchaksa.com`
- API Gateway custom domain target: `d-dom0cpkh9d.execute-api.ap-northeast-2.amazonaws.com`
- Scraper job queue: `https://sqs.ap-northeast-2.amazonaws.com/984762359128/prod-scraper-jobs`
- Scraper pipe: `arn:aws:pipes:ap-northeast-2:984762359128:pipe/prod-scraper-jobs-to-ecs`
- Scraper worker ECR: `984762359128.dkr.ecr.ap-northeast-2.amazonaws.com/prod-scraper-worker`
- Scraper worker cluster: `arn:aws:ecs:ap-northeast-2:984762359128:cluster/prod-scraper-cluster`
- Scraper worker task definition: `arn:aws:ecs:ap-northeast-2:984762359128:task-definition/prod-scraper-worker:2`
- Scrape result bucket: `cck-prod-scrape-results-984762359128`
- Scrape result prefix: `prod/`

## 후속 작업

- prod backend Lambda에 필요한 실제 운영 환경변수 전체를 백엔드 저장소/운영 secret 기준으로 확정한다.
- prod scraper worker 이미지를 ECR에 push하고 `image_uri`를 실제 sha 태그로 변경한다.
- Grafana Cloud prod stack/token을 준비하면 `backend_serverless.grafana_cloud`를 별도 작업으로 활성화한다.
- maintenance handler 배포 후 scheduler `state`를 `ENABLED`로 전환한다.
- prod backend 배포 workflow로 새 Lambda version을 publish하고 `live` alias를 갱신한다.
- 검증 완료 후 별도 승인으로 Route53/API Gateway cutover를 진행한다.
