# AGENTS.md

이 문서는 이 저장소의 통합 지침서다. 아래 규칙은 작업 시 강제 적용한다.

## 1. 기본 원칙
- 운영 영향 최소화: 병행 구축, 점진 전환, 즉시 롤백 가능 상태 유지
- shadow 테스트 리소스 접두어는 `develop-shadow`로 고정
- 운영 반영은 검증 게이트를 통과한 경우에만 수행

## 2. 현재/목표 구조
- 현재 백엔드 구조: `EC2 + ASG(min=1) + ALB`
- 현재 스크래핑 구조: `ECS Fargate Service(상시) + ALB`
- 목표 스크래핑 구조: `Backend API -> SQS -> ECS RunTask(Fargate) -> Backend Result API -> DB`
- 목표 백엔드 구조: `API Gateway + Lambda (+ 필요 시 SQS)`

## 3. 모듈 구조
- `component/`: 기존 운영 인프라 모듈
- `modules/scraper_async/`: 스크래핑 비동기 전환 모듈(SQS/DLQ/Pipe/RunTask + ECR 연동)
- `modules/scraper_worker/`: 스크래핑 워커 실행 모듈(ECS Cluster/TaskDefinition/IAM/Logs)
- `modules/backend_serverless/`: 백엔드 서버리스 전환 모듈(API Gateway/Lambda/옵션 큐)
- `scrape_result_storage`: 스크래핑 결과 저장 버킷(S3 + IAM + env 주입, develop-shadow/prod 승인 적용)
- `backend/backend-develop-shadow.hcl`: develop-shadow 상태 key 분리 설정
- `tfvars/develop-shadow.tfvars.example`: develop-shadow 적용 전용 변수 예시 파일(실제 `tfvars/develop-shadow.tfvars`는 민감값 포함 가능성이 있어 Git에 올리지 않음)
- `tfvars/prod.tfvars.example`: prod 서버리스 병행 리소스 사전 세팅 예시 파일(실제 `tfvars/prod.tfvars`는 민감값 포함 가능성이 있어 Git에 올리지 않음)
- shadow 상태를 사용할 때는 `environment=develop-shadow`, `enable_develop=false`로 설정하고 루트에서 `module.component`를 비활성화한다
- 스크래핑 모듈 입력 원칙:
  - 루트 변수 `scraper_async` 객체 1개로 최소 필수값만 전달
  - 워커 리소스 자동 생성 시 루트 변수 `scraper_worker` 객체 사용
  - 큐 이름/리텐션/배치/pipe 상태 등은 모듈 내부 기본값 사용
  - `enable_scraper_async=true`일 때 필수 참조값(Cluster/TaskDefinition/Role/Subnet/SG/Prefix) 누락 금지
  - 결과물 S3 저장은 `scrape_result_storage.enabled=true`로 토글하며 `bucket_name`을 비우면 `cck-<environment>-scrape-results-<account_id>` 네이밍을 자동 사용한다(기본 prefix는 `<environment>/`)
  - 해당 버킷은 Public Access Block + AES256 기본 암호화 + 30일 lifecycle 규칙을 고정으로 유지한다
  - `scrape_result_storage` 활성화 시 워커/Lambda IAM에 prefix 범위 한정 S3 권한이 자동 부여되고 `SCRAPING_RESULT_*` env가 자동 주입되므로 모듈 밖에서 수동 env/권한을 중복 추가하지 않는다
- 워커 시크릿 입력 원칙:
  - `scraper_worker.task_secrets`로 ECS container secrets(`name` -> `valueFrom ARN`)를 주입
  - `task_secrets`를 사용할 때 execution role에 해당 secret ARN에 대한 읽기 권한(`secretsmanager:GetSecretValue` 또는 `ssm:GetParameters`)이 함께 부여되어야 한다
- 스크래핑 코드 재배포 시 이미지 갱신은 스크래핑 리포지토리 CI에서 `register-task-definition` + `update-pipe`로 처리하고, Terraform apply는 인프라 변경 시에만 수행
- Pipe IAM 정책의 `ecs:RunTask` 리소스는 특정 revision이 아니라 task definition family 전체 revision(`:*`)을 허용해야 한다
- `aws_pipes_pipe`의 최신 `task_definition_arn`과 container override(`SQS_MESSAGE_BODY`, `SQS_MESSAGE_ID`)는 CI가 관리하므로 Terraform은 drift를 무시해야 한다
- 백엔드 서버리스 입력 원칙:
  - 루트 변수 `backend_serverless` 객체 1개로 최소 필수값만 전달
  - runtime/handler/timeout/async 큐 정책값은 모듈 내부 기본값 사용
  - memory/예약 동시 실행 수는 모듈 기본값을 우선 사용하되, shadow 환경의 기존 운영값을 유지해야 할 때만 tfvars에서 명시 override 한다
  - `enable_backend_serverless=true`일 때 `app_name`, `lambda_package_path`, `custom_domain_name`, `certificate_arn` 누락 금지
  - Supabase 외부 연결 기준으로 Lambda는 기본적으로 VPC에 넣지 않는다
  - `modules/backend_serverless`는 SnapStart, API Gateway custom domain, API mapping을 기본 지원한다
  - Lambda 패키지가 직접 업로드 한도를 넘는 경우를 대비해 `modules/backend_serverless`는 전용 S3 artifact bucket/object를 통해 배포한다
  - Lambda Grafana Cloud 연동은 `backend_serverless.grafana_cloud` 객체로 관리하며 extension layer ARN, instance ID, OTLP endpoint, API key secret ARN을 함께 전달한다
  - Lambda maintenance 작업 전환은 `backend_serverless.maintenance_schedules` 객체로 관리하며 EventBridge Scheduler가 `live` alias를 직접 invoke한다
  - Grafana Cloud API key는 코드/평문 tfvars에 두지 않고 Secrets Manager ARN으로만 주입하며, Lambda role에는 `secretsmanager:GetSecretValue` 권한을 부여한다
  - 스크래핑 비동기 백엔드 연동 시 `SCRAPING_JOB_QUEUE_URL`은 스크래핑 모듈 출력값을 우선 사용하고, Lambda role에는 대상 큐에 대한 `sqs:SendMessage/GetQueueAttributes/GetQueueUrl` 권한이 함께 부여되어야 한다
  - 신규 큐를 같은 apply에서 생성할 수 있으므로 Lambda SQS env/IAM 생성 여부는 queue ARN 값 자체가 아니라 명시 boolean 입력으로 제어한다
  - S3 기반 스크래핑 결과 저장소는 루트 변수 `scrape_result_storage`로 관리하고, bucket/prefix/timeout 환경변수는 백엔드 Lambda와 scraper worker에 공통 주입한다
  - `SCRAPING_CALLBACK_HMAC_SECRET`은 코드 저장소에 평문으로 두지 않고 Secrets Manager ARN을 통해 Lambda 환경변수로 주입한다
  - Lambda Actuator health는 `/var/task` diskSpace 검사를 운영 정상성 기준으로 쓰지 않도록 `MANAGEMENT_HEALTH_DISKSPACE_ENABLED=false`를 명시한다
  - `develop-shadow` 백엔드 Lambda 코드는 백엔드 저장소 CI가 배포하므로 Terraform은 `aws_s3_object.lambda_package`, `aws_lambda_function.backend`의 코드 관련 속성, `aws_lambda_alias.live.function_version` 드리프트를 무시하고 인프라/환경변수만 관리한다

## 4. 브랜치/커밋/PR 규칙
- 브랜치 규칙: `feat/<번호>`
- 커밋 메시지 규칙: `'<번호> <type>: <한글 메시지>'`
- PR 작성 시 프로젝트 PR 템플릿이 있으면 반드시 따름
- PR 필수 포함 항목:
  - 변경 요약
  - 영향 범위
  - 롤백 방법
  - 검증 증적(plan/log/테스트 결과)
  - 관련 context 파일 경로
  - `AGENTS.md 업데이트 필요 여부` 체크 결과

## 5. 작업 규칙
- 운영 리소스 직접 수정 금지(병행 리소스 생성 후 전환)
- 예상치 못한 변경 발견 시 즉시 중단 후 공유
- 모든 작업은 double check 수행(포맷/검증/영향 확인)
- 스크래핑 전환 시 워커 스펙은 `Fargate 1 vCPU / 2GB`, 접두어는 shadow는 `develop-shadow-*`, prod는 `prod-*`를 기본값으로 사용
- 결과 저장 버킷은 shadow/prod 병행 리소스로만 생성하고, 운영 트래픽 전환은 별도 승인 후 적용한다
- 운영 Launch Template은 콘솔 수동 관리 정책을 적용하며 Terraform은 LT 드리프트 감지/적용을 제외한다(`ignore_changes = all`)

## 6. Context 문서 규칙
- 컨텍스트 메타 규칙은 `docs/CONTEXT.md`를 따른다.
- 작업 기록은 반드시 `docs/{작업명}-context.md` 파일에 작성한다.
- 파일명은 kebab-case 권장 (예: `scraper-async-migration-context.md`)

## 7. AGENTS.md 갱신 의무
- 변경 사항이 생기면 `AGENTS.md`를 즉시 업데이트한다.
- 적용 조건:
  - As-Is/To-Be 구조 변경
  - 모듈/디렉터리 구조 변경
  - 브랜치/커밋/PR 규칙 변경
  - 운영 전환/롤백/검증 기준 변경
