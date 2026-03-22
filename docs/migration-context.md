# migration-context.md

- status: in-progress
- updated_at: 2026-03-03 Asia/Seoul

## 배경
- 현재 운영 구조는 상시 서버 기반이라 저트래픽 구간에서도 고정비가 발생한다.
- 운영 영향 없이 비용 절감을 위해 스크래핑 서버를 먼저 비동기/온디맨드 구조로 전환하고, 이후 백엔드 서버를 서버리스 중심으로 전환한다.
- 테스트는 운영 계정 내 shadow 환경에서 진행하며 리소스 접두어는 `develop-shadow`를 사용한다.

## 범위
- 포함:
  - 스크래핑 선행 -> 백엔드 후행 마이그레이션 전략
  - shadow 환경(`develop-shadow`) 기준 인프라/전환 원칙
  - 점진 전환 게이트 및 롤백 기준
  - 문서/운영 규칙(AGENTS.md, CONTEXT 규칙)
- 제외:
  - 실제 애플리케이션 코드 구현 상세(백엔드/프론트 비즈니스 로직)
  - 즉시 운영 전환 실행

## 현재 인프라 사실관계
1. 백엔드 현재 구조
- `EC2 t3.small` (`component/launch-template.tf`)
- `ASG min=1, desired=1, max=2` (`component/asg.tf`)
- `ALB + HTTP/HTTPS 리스너 + Target Group` (`component/alb.tf`, `component/listener-http.tf`, `component/alb-listener-https.tf`, `component/target-group.tf`)

2. 네트워크 현재 구조
- 단일 VPC + public/private subnet + IGW (`component/vpc.tf`)

3. 마이그레이션 모듈 현황
- 스크래핑 비동기 모듈: `SQS + DLQ + EventBridge Pipe + ECS RunTask` (`modules/scraper_async/main.tf`)
- 스크래핑 워커 모듈: `ECS Cluster + TaskDefinition + IAM + CloudWatch Logs` (`modules/scraper_worker/main.tf`)
- 백엔드 서버리스 모듈: `Lambda + API Gateway + optional SQS` (`modules/backend_serverless/main.tf`)
- 기본 토글 OFF: `enable_scraper_async=false`, `enable_scraper_worker_infra=false`, `enable_backend_serverless=false`

4. 누락/사전 필요 항목
- 스크래핑 워커 이미지 빌드/푸시 파이프라인 필요
- `subnet/sg` 값은 환경별로 확정 후 주입 필요

## 정정 (2026-03-03)
- 스크래핑 워커 ECR 리포지토리는 Terraform에 추가 완료:
  - `modules/scraper_async/main.tf`의 `aws_ecr_repository.worker`, `aws_ecr_lifecycle_policy.worker`
  - 출력값: `modules/scraper_async/outputs.tf`의 `worker_ecr_repository_url`
  - 루트 출력: `outputs.tf`의 `scraper_worker_ecr_repository_url`
- `develop-shadow` 상태 분리를 위한 backend 설정 파일 추가:
  - `backend/backend-develop-shadow.hcl`
  - state key: `terraform/develop-shadow/terraform.tfstate`
- `develop-shadow` 전용 변수 파일 추가:
  - `tfvars/develop-shadow.tfvars`
  - 접두어 고정: `develop-shadow-scraper`
- 스크래핑 워커 실행 모듈 추가:
  - `modules/scraper_worker/main.tf`
  - `enable_scraper_worker_infra=true`면 ECS cluster/task role/task definition 자동 생성

## As-Is
- 백엔드: `EC2 + ASG(min=1) + ALB` 상시 운영
- 스크래핑: `ECS Fargate Service(상시) + ALB` 상시 운영
- 고정비가 트래픽 대비 크게 발생

## To-Be
- 1단계(스크래핑):
  - `Backend API(접수) -> SQS -> ECS RunTask(Fargate) -> Backend Result API -> DB`
  - 재시도/DLQ/visibility timeout 기반 복구
  - 기존 경로 병행 유지 후 점진 전환
- 2단계(백엔드):
  - `API Gateway HTTP API + Lambda(Java 17, arm64, alias=live) (+ 필요 시 SQS)`
  - Lambda는 Supabase 외부 연결 기준 비VPC 유지
  - `dev.api.cchaksa.com -> API Gateway custom domain`으로 shadow 접근 경로 고정
  - 지연 민감 API는 Provisioned Concurrency(필요 시간대만), 기본은 SnapStart 중심

## 사전 작업 체크리스트(공통)
- `develop-shadow-*` 네이밍 및 태그(`Environment=develop-shadow`) 고정
- Terraform state 분리(key/workspace) 및 접근 권한 분리
- 비용/알람 기준 태그 분리(`Environment=develop-shadow`)
- 롤백 커맨드/소유자/타임윈도우 확정
- 데이터 분리 정책 확정(Supabase schema 또는 별도 프로젝트)

## 사전 작업 체크리스트(스크래핑)
- 이미지 저장소 준비(ECR 생성 또는 외부 레지스트리 선택)
- 스크래핑 워커 이미지 빌드/푸시 파이프라인 준비
- `enable_scraper_worker_infra=true` 사용 시 ECS Cluster/TaskDefinition/Role 자동 생성
- `enable_scraper_worker_infra=false` 사용 시 ECS Cluster ARN / TaskDefinition ARN / TaskRole/ExecutionRole ARN 수동 확보
- RunTask 대상 subnet/sg 확정
- 백엔드 내부 결과 수신 API 인증 방식(HMAC/JWT) 확정

## 사전 작업 체크리스트(백엔드)
- Lambda zip 빌드 산출물 경로 확정
- API Gateway 도메인/경로 전략 확정(기존 계약 호환)
- Provisioned Concurrency 적용 시간대 정책 확정
- 비동기 보조 큐 사용 여부 확정
- 백엔드 애플리케이션 Lambda 핸들러/패키징 방식 확정

## 신규 인프라 목록(단계별)
1. 스크래핑 1단계
- SQS 작업 큐: 이미 코드화됨 (`modules/scraper_async`)
- SQS DLQ: 이미 코드화됨 (`modules/scraper_async`)
- EventBridge Pipe: 이미 코드화됨 (`modules/scraper_async`)
- Pipe IAM Role/Policy: 이미 코드화됨 (`modules/scraper_async`)
- 워커 ECS Cluster/TaskDefinition/IAM/Logs: 이미 코드화됨 (`modules/scraper_worker`)
- 워커 이미지 배포(ECR push): 추가 필요(배포 파이프라인)

2. 백엔드 2단계
- Lambda + Alias: 이미 코드화됨 (`modules/backend_serverless`)
- API Gateway HTTP API: 이미 코드화됨 (`modules/backend_serverless`)
- Lambda IAM Role/기본 로그: 이미 코드화됨 (`modules/backend_serverless`)
- optional async SQS/DLQ: 이미 코드화됨 (`modules/backend_serverless`)
- API Gateway custom domain/API mapping: 이미 코드화됨 (`modules/backend_serverless`)
- Lambda artifact S3 bucket/object: 이미 코드화됨 (`modules/backend_serverless`)
- Cloudflare CNAME 반영: 추가 필요(도메인 운영 반영)

## 작업 순서(실행 순서 고정)
1. 기준선 측정
- 현재 요청량/오류율/p95/월비용 기준값 기록(날짜 포함)

2. 스크래핑 사전 준비
- 이미지 저장소(ECR 또는 외부) 준비
- 워커 이미지 빌드/푸시
- ECS TaskDefinition/Role/Subnet/SG 준비

3. 스크래핑 shadow 인프라 배포
- `enable_scraper_async=true`로 develop-shadow 경로만 활성화
- 운영 트래픽 연결 금지 상태로 배포

4. 스크래핑 기능 검증
- 정상/실패/중복/재시도/DLQ/heartbeat 검증

5. 스크래핑 점진 전환
- `1% -> 10% -> 30% -> 50% -> 100%`
- 단계별 게이트 통과 시에만 승급

6. 스크래핑 안정화
- 100% 후 48시간 관측
- 문제 없을 때 기존 스크래핑 상시 리소스 제거

7. 백엔드 사전 준비
- Lambda 패키지/환경변수/도메인 경로 확정

8. 백엔드 shadow 인프라 배포
- `enable_backend_serverless=true`로 병행 배포

9. 백엔드 호환 검증
- 기존 API 계약 호환 + 지표 검증

10. 백엔드 점진 전환
- `1% -> 10% -> 30% -> 50% -> 100%`

11. 백엔드 안정화 및 정리
- 48시간 관측 후 기존 EC2/ASG/ALB 제거

12. 최종 보고
- 전/후 비용, 성능, 장애지표, 남은 리스크 기록

## 게이트 및 실패 기준(정량)
- 성공률: 99% 이상 유지
- 5xx: 기준선 대비 악화 없음
- p95: 기준선 대비 허용 임계치(사전 확정값) 초과 없음
- DLQ: 급증 없음(사전 확정 임계치 초과 시 즉시 중단)
- 기준 위반 시: 즉시 전환 중단 + 롤백 실행(목표 5분 내)

## 운영 전환 후 정리 기준
- 100% 전환 후 48시간 안정화 통과
- 제거 순서:
  - 스크래핑: 기존 ALB -> 상시 ECS Service 관련 리소스
  - 백엔드: 기존 ALB -> ASG -> LaunchTemplate/부속 리소스
- 제거 후 비용/성능 재측정 및 보고서 확정

## 공개 API/인터페이스 변경
1. 스크래핑 완전 비동기 전환 시
- 백엔드에 Job 상태 인터페이스 필요
- 결과 콜백 내부 API 필요

2. 백엔드 서버리스 전환 시
- 외부 API 계약은 유지 원칙
- 내부 실행 경로만 `EC2 -> Lambda`로 변경

## 테스트 케이스 및 시나리오
1. 스크래핑
- 정상 처리
- 외부 포털 실패
- 메시지 중복 전달
- visibility timeout 초과 상황 heartbeat
- DLQ 재처리

2. 백엔드
- 기존 API 계약 회귀
- cold start 영향 측정(p95/p99)
- PC 적용 시간대와 비적용 시간대 성능 비교

3. 전환
- 단계별 카나리 승급/중단/롤백 실습
- 롤백 5분 이내 복귀 검증

## 명시적 가정/기본값
1. 리전은 `ap-northeast-2` 유지
2. shadow 접두어는 `develop-shadow` 고정
3. 운영 계정 내 병행 구축 방식 유지
4. 스크래핑 선행 완료 전 백엔드 전환 착수 금지
5. 구조/규칙 변경 시 `AGENTS.md` 동기화 필수
6. 스크래핑 워커 스펙은 `Fargate 1 vCPU / 2GB` 고정(워크로드 TaskDefinition에서 강제)
7. 결과 콜백 인증은 `HMAC 서명` 고정
8. Supabase는 기존 schema 공용 사용, 테스트 데이터 식별/정리 규칙 강제

## 고정 결정값 (develop-shadow 즉시 착수)
1. 컨테이너 레지스트리: `ECR 신규 생성`
2. Terraform 상태 분리: `prod state 버킷 내 key 분리`
3. 트래픽 전환: `백엔드 feature flag`
4. 워커 스펙: `Fargate 1 vCPU / 2GB`
5. 결과 콜백 인증: `HMAC`
6. 데이터 분리: `Supabase 공용 schema + 테스트 데이터 식별/정리`
7. 리전/네이밍: `ap-northeast-2`, `develop-shadow-*`

## 공개 API/인터페이스 상세 (스크래핑 비동기)
1. 백엔드 외부 API
- `POST /portal/link`: 즉시 접수 응답(`job_id`, `status=accepted`)
- `GET /portal/link/jobs/{job_id}`: 상태 조회(`queued`, `running`, `succeeded`, `failed`)
2. 백엔드 내부 API
- `POST /internal/scrape-results`: 워커 결과 콜백 수신(`HMAC` 검증 필수)
3. 데이터 모델
- `scrape_job`(또는 동등 테이블): 상태 전이, 재시도 횟수, 에러코드, 타임스탬프

## 기준선 측정 항목 (1단계 시작 전 필수)
- 측정일시/환경:
  - `TODO: YYYY-MM-DD HH:mm Asia/Seoul / prod`
- 요청량(24h), 성공률, 5xx, p95, 월 비용:
  - `TODO: CloudWatch + 비용 데이터 입력`
- 기록 위치:
  - 본 문서 `실행 로그`와 최종 보고에 동일 값 사용

## 작업 순서 상세(고정)
1. 기준선 측정 및 기록
2. 스크래핑 사전 준비(ECR/이미지/TaskDefinition/Role/Subnet/SG/HMAC)
3. shadow 인프라 배포(`enable_scraper_async=true`, 운영 트래픽 미연결)
4. 기능/복구 검증(정상/실패/중복/visibility timeout/DLQ)
5. 점진 전환(`1% -> 10% -> 30% -> 50% -> 100%`, 단계당 30~120분 관측)
6. 100% 전환 후 48시간 안정화 관측
7. 기존 상시 스크래핑 리소스(ALB/Service) 제거
8. 이후 백엔드 서버리스 전환 착수

## 게이트/중단 기준 상세(고정)
- 성공률 `>= 99%`
- 5xx 악화 없음(기준선 대비)
- p95 악화 없음(사전 합의 임계치 초과 금지)
- DLQ 급증 없음(임계치 초과 시 즉시 중단)
- 롤백 목표시간: `5분 이내`

## 실행 로그

### 2026-03-15 - develop-shadow 백엔드 스크래핑 enqueue 권한/환경변수 코드화
- 배경:
  - dev Lambda가 `POST /portal/link`에서 `SCRAPE_JOB_ENQUEUE_FAILED`로 종료
  - 수동으로 넣은 `SCRAPING_JOB_QUEUE_URL`, `SCRAPING_CALLBACK_HMAC_SECRET`는 다음 Terraform apply 시 유실될 상태였음
- 반영:
  - `modules/backend_serverless`에 스크래핑 큐 URL/HMAC secret ARN 입력 추가
  - Lambda environment에 `SCRAPING_JOB_QUEUE_URL`, `SCRAPING_CALLBACK_HMAC_SECRET` 자동 병합
  - Lambda execution role에 대상 큐 `sqs:SendMessage`, `sqs:GetQueueAttributes`, `sqs:GetQueueUrl` 권한 추가
  - 루트 모듈에서 `scraper_async` 출력(queue URL/ARN)과 `scraper_worker.task_secrets.SCRAPE_CALLBACK_HMAC_SECRET`를 `backend_serverless`로 자동 연결
- 기대 효과:
  - dev Lambda가 같은 계정의 `develop-shadow-scraper-jobs`로 직접 enqueue 가능
  - 수동 설정 drift 없이 다음 apply 후에도 스크래핑 비동기 연동 설정 유지

### 2026-03-15 - develop-shadow scraper worker execution role SSM 권한 보강
- 배경:
  - `job_id=e84d3040-490e-4b99-a8d2-72da944d1252` 처리 시 ECS task가 `ResourceInitializationError`로 시작 전 실패
  - 원인 로그: `develop-shadow-scraper-worker-exec-role`에 `ssm:GetParameters` 권한이 없어서 secret 초기화 실패
- 원인 상세:
  - 기존 execution role 정책이 `ssm:GetParameters`를 포함하더라도 리소스가 Secrets Manager ARN 하나로 묶여 있어 실제 SSM ARN과 매칭되지 않았음
- 반영:
  - `modules/scraper_worker` execution secret access 정책을 분리
  - `secretsmanager:*`는 secret ARN에 한정
  - `ssm:GetParameters`는 ECS 초기화 단계에서 실제 평가되는 SSM 리소스 ARN 형식에 맞춰 `arn:aws:ssm:${region}:${account}:*` 범위 허용

### 2026-03-22 - develop-shadow Lambda 실제 환경변수 코드화
- 배경:
  - `terraform plan -var-file=tfvars/develop-shadow.tfvars` 시 `module.backend_serverless[0].aws_lambda_function.backend`가 실제 Lambda env와 달라 대량 환경변수 삭제 drift를 표시
  - 특히 `APP_KEY`, `APP_NATIVE_KEY`, `DEV_DB_*`, `JWT_*`, `REDIS_ENCRYPT_KEY` 등이 tfvars에 없어 apply 시 유실 위험이 있었음
- 반영:
  - `tfvars/develop-shadow.tfvars`의 `backend_serverless.lambda_environment`를 현재 `develop-shadow-develop-shadow-api` Lambda 설정 기준으로 보강
  - `SCRAPING_JOB_QUEUE_URL`, `SCRAPING_CALLBACK_HMAC_SECRET`는 모듈의 자동 주입 경로를 유지하고 나머지 런타임 env만 명시
- 기대 효과:
  - develop-shadow plan/apply 시 실제 Lambda 환경변수 유실 방지
  - Lambda env의 소스 오브 트루스를 tfvars로 정리

### 2026-03-22 - develop-shadow Lambda 코드/alias drift 무시 정책 채택
- 배경:
  - 백엔드 저장소 CI가 `develop-shadow-develop-shadow-api` 코드를 직접 배포하면서 Lambda version, alias `live`, artifact object가 Terraform state와 분리됨
  - 동일 시점에 Terraform apply를 수행하면 현재 정상 동작 중인 Lambda 코드가 로컬 패키지 기준 새 버전으로 다시 덮어써질 위험이 있었음
- 반영:
  - `modules/backend_serverless`에 lifecycle ignore 규칙 추가
  - `aws_s3_object.lambda_package`: `key`, `source`, `etag`, `version_id` drift 무시
  - `aws_lambda_function.backend`: `source_code_hash`, `s3_key`, `s3_object_version`, `last_modified`, `qualified_arn`, `qualified_invoke_arn`, `version` drift 무시
  - `aws_lambda_alias.live`: `function_version` drift 무시
- 운영 원칙:
  - Lambda 코드는 백엔드 저장소 CI가 배포
  - Terraform은 API Gateway, IAM, env, queue wiring 등 인프라 설정만 관리
- 2026-03-03:
  - 마이그레이션 방향 확정: 스크래핑 선행, 백엔드 후행
  - shadow 네이밍 확정: `develop-shadow`
  - 문서 체계 확정: `AGENTS.md` + `docs/CONTEXT.md` + 작업별 `docs/{작업명}-context.md`
  - 요청 사항 반영: 변경 사항 발생 시 `AGENTS.md` 갱신 의무 추가
  - 스크래핑 변수 구조 리팩터링:
    - 개별 변수 다수 -> `scraper_async` 객체 1개로 단순화
    - queue/dlq 네이밍 및 pipe 튜닝값은 모듈 내부 기본값으로 고정
  - 백엔드 서버리스 변수 구조 리팩터링:
    - 개별 변수 다수 -> `backend_serverless` 객체 1개로 단순화
    - runtime/handler/memory/timeout/async 큐 튜닝값은 모듈 내부 기본값으로 고정
  - 본 문서 보강:
    - 현재 인프라 사실관계/사전 작업/신규 인프라/고정 작업순서/정량 게이트 추가
  - `develop-shadow` 즉시 착수 IaC 반영:
    - `backend/backend-develop-shadow.hcl` 추가(상태 key 분리)
    - `tfvars/develop-shadow.tfvars` 추가(접두어/프로필/기본값 고정)
    - `modules/scraper_async`에 ECR 리포지토리/라이프사이클 정책 추가
    - 루트 출력값 `scraper_worker_ecr_repository_url` 추가
    - 변수 검증 강화:
      - `enable_scraper_async=true` 시 필수 참조값 누락 방지
      - `enable_backend_serverless=true` 시 필수 산출물 경로 누락 방지
  - 스크래핑 워커 인프라 자동 생성 경로 추가:
    - `enable_scraper_worker_infra=true` 시 ECS Cluster/TaskDefinition/IAM/Logs 생성
    - `enable_scraper_async` 모듈과 워커 모듈 연동(수동 ARN 주입 최소화)
  - 운영값 고정 반영:
    - `tfvars/prod.tfvars`에 scraper async/worker 활성값 및 subnet/sg/name_prefix 반영
    - 워커 런타임 env/secret 템플릿(`SCRAPE_CALLBACK_*`, timeout, graceful shutdown) 반영
  - 워커 시크릿 주입 경로 추가:
    - `modules/scraper_worker`에 `task_secrets` 추가(ECS container secrets)
  - 제한사항 확인:
    - Terraform `aws_pipes_pipe` ECS 파라미터에서 task override/env 주입 블록 미지원(현재 provider 스키마 기준)
  - 배포 전략 확정:
    - 스크래핑 코드 재배포는 스크래핑 리포지토리 CI에서 처리(`ECR push -> ECS register-task-definition -> EventBridge Pipe update`)
    - Terraform apply는 인프라 구조 변경 시에만 수행
  - 운영 Launch Template 드리프트 비노출 정책 채택:
    - 대상: `component/launch-template.tf`의 `aws_launch_template.app`
    - 변경: `lifecycle.ignore_changes = all`
    - 이유: 운영 AMI/LT는 콘솔 수동 변경을 허용하고 plan 노이즈를 제거하기 위함
    - 영향: LT 관련 코드 변경(`instance_type`, `user_data`, `network_interfaces` 포함)은 Terraform apply로 반영되지 않음
- 2026-03-10:
  - `develop-shadow` 스크래핑 테스트값 고정:
    - `environment=develop-shadow`, `enable_develop=false`로 shadow 상태에서 기존 `component` 스택 생성을 차단
    - 루트 `module.component`를 count 기반으로 비활성화해 shadow에서 ALB/ASG/VPC가 함께 생성되지 않도록 수정
    - `tfvars/develop-shadow.tfvars`에서 `enable_scraper_async=true`
    - `subnet_ids`, `security_group_ids`는 운영 VPC 공용 값 사용
    - 워커 런타임 env에 `WORKER_INPUT_MODE=pipe`, `SCRAPE_CALLBACK_BASE_URL=https://dev.api.cchaksa.com` 반영
    - 워커 이미지 URI 기본값은 `develop-shadow-scraper-worker:bootstrap`으로 지정
    - HMAC secret은 기존 운영 계정 secret ARN을 임시 공용 참조로 지정
  - shadow 리소스 이름 기준 재확인:
    - ECR: `develop-shadow-scraper-worker`
    - Queue: `develop-shadow-scraper-jobs`
    - Pipe: `develop-shadow-scraper-jobs-to-ecs`
    - Cluster: `develop-shadow-scraper-cluster`
    - Task Family: `develop-shadow-scraper-worker`
    - Log Group: `/ecs/develop-shadow-scraper-worker`
  - `prod-*` 비동기 리소스 선제 정리:
    - `tfvars/prod.tfvars`에서 `enable_scraper_async=false`, `enable_scraper_worker_infra=false`로 변경
    - `module.component -> module.component[0]` 주소 이동으로 인한 운영 스택 재생성 plan을 막기 위해 루트 `moved` 블록 추가
    - `terraform apply -var-file=tfvars/prod.tfvars -auto-approve` 결과 `0 add / 0 change / 13 destroy`
    - 제거 대상은 `prod-scraper-*` 비동기 리소스(ECR, SQS/DLQ, Pipe, ECS Cluster/TaskDefinition, worker IAM/Logs)로 한정
    - 목적: shadow 테스트 전 `prod-*` 비동기 리소스와의 혼선 제거, 운영 미사용 리소스 정리
  - `develop-shadow` shadow 리소스 배포 완료:
    - `terraform apply -var-file=tfvars/develop-shadow.tfvars -auto-approve` 결과 `13 add / 0 change / 0 destroy`
    - 생성 리소스: `develop-shadow-scraper-worker` ECR, `develop-shadow-scraper-jobs`, DLQ, Pipe, ECS Cluster, TaskDefinition, IAM role, 로그 그룹
    - ECS task secret `SCRAPE_CALLBACK_HMAC_SECRET` 주입 확인
  - 스크래핑 GitHub Actions용 IAM 사용자 생성:
    - 사용자명: `develop-shadow-scraper-github-actions`
    - 용도: 스크래핑 리포 CI의 shadow 배포(ECR push, ECS task definition 등록, Pipe 갱신)
    - 권한 범위: `develop-shadow-scraper-worker` ECR, `develop-shadow-scraper-jobs-to-ecs` Pipe, shadow worker role `iam:PassRole`, `ecs:RegisterTaskDefinition`, `ecs:DescribeTaskDefinition`
  - shadow E2E 검증 중 발견된 수정사항:
    - Pipe는 큐 메시지를 소비했지만 ECS task가 생성되지 않음
    - 원인: `develop-shadow-scraper-pipe-role`의 `ecs:RunTask` 권한이 `develop-shadow-scraper-worker:1` revision에만 고정
    - 조치: `modules/scraper_async`에서 Pipe IAM policy의 `ecs:RunTask` 리소스를 task definition family 전체 revision(`:*`) 패턴으로 변경
    - 추가 조치: `aws_pipes_pipe`의 `task_definition_arn`과 `overrides`는 스크래핑 리포 CI가 관리하므로 Terraform `ignore_changes`로 drift를 무시
    - 기대 효과: 스크래핑 리포 CI가 `register-task-definition`으로 revision을 올려도 Terraform 재적용 없이 Pipe가 최신 revision 실행 가능
  - shadow task 기동 검증 중 추가 수정사항:
    - ECS task는 생성됐지만 `TaskFailedToStart`로 종료
    - 원인: `develop-shadow-scraper-worker-exec-role`에 `SCRAPE_CALLBACK_HMAC_SECRET` 조회 권한 부재
    - 조치: `modules/scraper_worker`에서 `task_secrets` 사용 시 execution role에 `secretsmanager:GetSecretValue`, `secretsmanager:DescribeSecret`, `ssm:GetParameters` 권한을 해당 secret ARN에 부여
  - 백엔드 서버리스 shadow 구조 반영:
    - `modules/backend_serverless`에 Lambda SnapStart(`PublishedVersions`) 추가
    - API Gateway HTTP API custom domain, API mapping, regional target output 추가
    - Lambda jar 크기가 직접 업로드 한도를 넘으므로 전용 S3 artifact bucket/object를 통해 배포하도록 보강
    - 루트 `backend_serverless` 객체에 `custom_domain_name`, `certificate_arn` 입력 추가
    - `tfvars/develop-shadow.tfvars`에 `enable_backend_serverless=true` 반영
    - `dev.api.cchaksa.com`과 ACM 인증서 ARN을 shadow 서버리스 입력으로 고정
    - Lambda 패키지 경로는 인접 백엔드 저장소의 Lambda 전용 산출물 `../haksa/build/distributions/haksa-lambda.zip`을 참조
    - Lambda는 Supabase 외부 연결 기준으로 비VPC 유지
  - 백엔드 애플리케이션 shadow 검증에서 확인한 필수 변경사항:
    - 인접 백엔드 저장소(`../haksa`)에는 별도 브랜치에서 아래 변경이 필요함
    - Lambda 전용 핸들러 `com.chukchuk.haksa.global.lambda.StreamLambdaHandler`
    - `aws-serverless-java-container-springboot3`, `aws-lambda-java-core` 의존성
    - `lambdaZip` task 및 클래스 루트 + `lib/` 의존성 구조 패키징
    - `develop-shadow -> dev` profile group
    - `LOG_PATH`, `LOG_FILE_NAME` 환경변수 기반 Logback 설정
  - 백엔드 서버리스 apply/런타임 검증 기록(임시 검증 결과):
    - 초기 direct upload는 Lambda `413 RequestEntityTooLarge`로 실패하여 S3 artifact 배포 경로로 전환
    - published version 1, 2는 bootJar/classpath 문제로 핸들러 클래스를 로드하지 못해 실패
    - published version 3은 Logback가 `/var/log/app`를 요구해 초기화 실패
    - published version 4, 5는 reactive management security와 MVC security 충돌로 실패
    - Lambda 애플리케이션 쪽에서 `spring.main.web-application-type=servlet` 강제가 필요함을 확인
    - 최신 published version 6은 Spring/JPA 초기화까지 진입했으나 `DEV_DB_*` 자격증명으로 Supabase 인증 실패(`FATAL: Tenant or user not found`)
    - 현재 `live` alias는 여전히 version `2`를 가리키며, shadow 백엔드 cutover는 보류 상태
  - 현재 제한사항:
    - 백엔드 앱 저장소 변경은 아직 별도 브랜치에 정식 반영되지 않았음
    - 유효한 `DEV_DB_URL/DEV_DB_USERNAME/DEV_DB_PASSWORD`가 확보되기 전까지 shadow 백엔드는 정상 기동할 수 없음

## 검증 결과
- 문서 규칙 검증:
  - `AGENTS.md` 생성 및 규칙 반영 완료
  - `docs/CONTEXT.md` 생성 및 파일명/기록 규칙 반영 완료
  - 작업 컨텍스트 파일 규칙 준수(`migration-context.md`)
- 인프라 검증:
  - 기존 운영 경로를 유지하는 병행 전환 원칙 채택
  - 실제 apply 전 단계(설계/문서) 기준으로 충돌 없음

## 롤백 계획
- 이상 감지 즉시 신규 경로 0% 복귀
- 기존 경로 100% 복원
- 데이터 정합성 확인 후 원인 분석/재진행
- 롤백 목표 시간: 5분 내

## 오픈 이슈
- 백엔드/프론트 비동기 계약 상세(job 상태 코드/에러 코드 표준) 확정 필요
- shadow 환경의 데이터 분리 수준(스키마 vs 별도 프로젝트) 최종 결정 필요
- 운영 cutover 타임윈도우/승인자 지정 필요
