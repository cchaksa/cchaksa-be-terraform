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
  - develop-shadow와 동일하게 `APPLE_ALLOWED_CLIENT_IDS=com.cchaksa.app,com.chukchukhaksa.moblie.ChukChukHaksa`를 prod Lambda env에 명시했다.
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
- GitHub Actions OIDC provider: `arn:aws:iam::984762359128:oidc-provider/token.actions.githubusercontent.com`
- Prod scraper deploy role: `arn:aws:iam::984762359128:role/prod-scraper-github-actions-role`

## 2026-05-11 prod scraper 배포 권한 보강

- `cchaksa/suwon-scraper-v1`의 prod 이미지 배포 workflow가 `develop-shadow-scraper-github-actions` access key를 사용하면서 `prod-scraper-worker` ECR push에 실패했다.
- 실패 지점:
  - `docker push`
  - `ecr:InitiateLayerUpload`
  - 대상: `arn:aws:ecr:ap-northeast-2:984762359128:repository/prod-scraper-worker`
- 원인:
  - 기존 IAM user `develop-shadow-scraper-github-actions`의 inline policy는 shadow ECR/Pipe/role만 허용한다.
  - prod workflow가 shadow 전용 credential을 재사용했다.
- 장기 access key를 추가 발급하는 대신 GitHub OIDC 기반 prod 전용 role을 생성했다.
  - role: `prod-scraper-github-actions-role`
  - trust principal: `token.actions.githubusercontent.com`
  - trust condition:
    - `token.actions.githubusercontent.com:aud = sts.amazonaws.com`
    - `token.actions.githubusercontent.com:sub = repo:cchaksa/suwon-scraper-v1:environment:prod`
  - inline policy: `prod-scraper-deploy`
- role 권한 범위:
  - `prod-scraper-worker` ECR push
  - `ecs:RegisterTaskDefinition`, `ecs:DescribeTaskDefinition`
  - `prod-scraper-jobs-to-ecs` Pipe describe/update
  - `prod-scraper-worker-exec-role`, `prod-scraper-worker-task-role` PassRole to `ecs-tasks.amazonaws.com`
  - `prod-scraper-pipe-role` PassRole to `pipes.amazonaws.com`
- GitHub `prod` environment variable에 아래 값을 등록했다.
  - `AWS_ROLE_ARN=arn:aws:iam::984762359128:role/prod-scraper-github-actions-role`
- 검증:
  - IAM role trust policy가 `repo:cchaksa/suwon-scraper-v1:environment:prod`로 제한된 것을 확인했다.
  - inline policy statement `EcrAuth`, `EcrPushProd`, `EcsTaskDefinition`, `PipeManageProd`, `AllowPassProdWorkerRoles`, `AllowPassProdPipeRole` 존재를 확인했다.
  - IAM policy simulation에서 prod ECR push, ECS task definition 등록, Pipe update, PassRole 권한이 `allowed`로 평가됨을 확인했다.
- 남은 작업:
  - 스크래핑 서버 저장소의 `deploy-prod.yml`에서 access key 방식 대신 OIDC role assume 방식으로 변경해야 한다.
  - workflow에 `permissions.id-token=write`, `permissions.contents=read`를 추가해야 한다.
  - `aws-actions/configure-aws-credentials`는 `role-to-assume: ${{ vars.AWS_ROLE_ARN }}` 방식으로 변경해야 한다.

## 2026-05-11 prod scraper OIDC workflow 적용 및 이미지 배포 검증

- 스크래핑 서버 저장소 `cchaksa/suwon-scraper-v1`의 `deploy-prod.yml`이 OIDC 방식으로 변경된 것을 확인했다.
  - `permissions.id-token=write`
  - `permissions.contents=read`
  - `aws-actions/configure-aws-credentials@v4`
  - `role-to-assume: ${{ vars.AWS_ROLE_ARN }}`
- 반영 커밋:
  - `5b1a5bcc55ceeef980b019c12fb41d2f15609928`
  - `10 fix: prod 배포 OIDC 인증 적용`
- prod 배포 workflow 실행 결과:
  - run id: `25634750726`
  - job id: `75244546846`
  - conclusion: `success`
  - duration: `2m25s`
- 배포 산출물:
  - image URI: `984762359128.dkr.ecr.ap-northeast-2.amazonaws.com/prod-scraper-worker:5b1a5bcc55ceeef980b019c12fb41d2f15609928`
  - task definition: `arn:aws:ecs:ap-northeast-2:984762359128:task-definition/prod-scraper-worker:3`
  - pipe: `prod-scraper-jobs-to-ecs`
- AWS 상태 검증:
  - ECR `prod-scraper-worker`에 image tag `5b1a5bcc55ceeef980b019c12fb41d2f15609928`가 존재한다.
  - image digest: `sha256:eed840bccd16be974207002da859e48791c5980faa9c9f943ee550a39e9f3c98`
  - image size: `728662259`
  - Pipe `prod-scraper-jobs-to-ecs`는 `RUNNING` 상태다.
  - Pipe target task definition은 `prod-scraper-worker:3`이다.
  - Pipe SQS batch size는 `1`, batching window는 `0`이다.
  - task definition `prod-scraper-worker:3`의 image, `SCRAPE_CALLBACK_HMAC_SECRET`, `SCRAPING_RESULT_BUCKET`, `SCRAPING_RESULT_PREFIX`, `SCRAPE_CALLBACK_BASE_URL=https://api.cchaksa.com` 값을 확인했다.

## 2026-05-11 prod Lambda scraping env 보강

- prod 전환 전 백엔드 Lambda에 스크래핑 런타임 환경변수 3개를 추가했다.
  - `SCRAPING_MODE=async`
  - `SCRAPING_PUBLISHER_ENABLED=true`
  - `SCRAPING_CALLBACK_ALLOWED_SKEW_SECONDS=300`
- 실제 `tfvars/prod.tfvars`에 값을 반영했고, 민감값 없는 예시 파일 `tfvars/prod.tfvars.example`에도 동일 키를 추가했다.
- 전체 Terraform apply는 shared prod state 전체에 영향을 줄 수 있어 수행하지 않았다.
- 대신 `prod-haksa-api` Lambda 함수 하나의 기존 환경변수에 3개 키만 병합 업데이트했다.
- 업데이트 후 새 Lambda version을 publish하고 `live` alias를 갱신했다.
  - published version: `7`
  - live alias: `7`
  - state: `Active`
  - last update status: `Successful`
- develop-shadow의 `SCRAPING_RESULT_API_CALL_ATTEMPT_TIMEOUT_SECONDS`는 `$LATEST`, `live` 모두 `30`인 것을 확인했다.
- prod도 `SCRAPING_RESULT_API_CALL_ATTEMPT_TIMEOUT_SECONDS=30`으로 유지했다.
- API Gateway health 확인:
  - endpoint: `https://51xqikq1h5.execute-api.ap-northeast-2.amazonaws.com/actuator/health`
  - HTTP status: `200`
  - health status: `UP`
  - DB status: `UP`

## 2026-05-11 prod scraper callback URL 임시 전환

- prod Lambda execute-api로 `/portal/link` 요청을 생성한 뒤 `job_id=8f12e751-fd45-43cc-94b7-9c14de1b3903` 작업을 점검했다.
- 확인 결과:
  - DB `scrape_jobs.status=RUNNING`
  - DB `scrape_job_outbox.status=SENT`
  - SQS message id: `7964cd6c-1134-4af2-8ef7-88bc3e7a1d38`
  - worker는 포털 스크래핑과 S3 업로드까지 성공했다.
  - result S3 key: `prod/8f12e751-fd45-43cc-94b7-9c14de1b3903/20260511T133644739.json`
  - callback 단계에서 `CALLBACK_NON_RETRYABLE:401`로 실패했다.
- 원인:
  - prod worker task definition `prod-scraper-worker:3`의 `SCRAPE_CALLBACK_BASE_URL`은 `https://api.cchaksa.com`이었다.
  - 현재 `api.cchaksa.com` DNS는 아직 API Gateway가 아니라 기존 prod ALB/EC2를 가리킨다.
  - 따라서 execute-api로 생성한 job도 worker callback은 기존 EC2 경로로 전송되어 401을 받았다.
- 임시 조치:
  - prod worker callback base URL을 `https://51xqikq1h5.execute-api.ap-northeast-2.amazonaws.com`으로 변경한다.
  - `tfvars/prod.tfvars`의 `scraper_worker.image_uri`는 현재 성공 배포된 image tag `5b1a5bcc55ceeef980b019c12fb41d2f15609928`로 맞춘다.
  - live AWS에는 현재 task definition `prod-scraper-worker:3`을 복제해 callback URL만 바꾼 `prod-scraper-worker:4`를 등록했다.
  - Pipe `prod-scraper-jobs-to-ecs` target task definition을 `prod-scraper-worker:4`로 갱신했다.
  - 검증 결과 Pipe 상태는 `RUNNING`이고, `prod-scraper-worker:4`의 `SCRAPE_CALLBACK_BASE_URL`은 execute-api 주소다.
  - 이후 Route53 전환이 완료되면 `SCRAPE_CALLBACK_BASE_URL`은 다시 `https://api.cchaksa.com`으로 되돌린다.

## 후속 작업

- prod backend Lambda에 필요한 실제 운영 환경변수 전체를 백엔드 저장소/운영 secret 기준으로 확정한다.
- prod scraper worker 배포 workflow OIDC 전환과 이미지 push, Pipe task definition 갱신은 완료했다.
- Grafana Cloud prod stack/token을 준비하면 `backend_serverless.grafana_cloud`를 별도 작업으로 활성화한다.
- maintenance handler 배포 후 scheduler `state`를 `ENABLED`로 전환한다.
- prod backend 배포 workflow로 새 Lambda version을 publish하고 `live` alias를 갱신한다.
- 검증 완료 후 별도 승인으로 Route53/API Gateway cutover를 진행한다.
