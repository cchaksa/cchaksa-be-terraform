# 마이그레이션 런북 (스크래핑 선행 -> 백엔드 후행)

## 1. 목적
- 스크래핑 서버를 완전 비동기/온디맨드 구조로 먼저 전환한다.
- 안정화 이후 백엔드 서버를 서버리스 중심 구조로 전환한다.
- 기존 운영 서비스는 병행 유지하고 점진 전환한다.

## 2. 기존 구조와 목표 구조
### 2.1 스크래핑 서버
- 기존: 상시 `ECS Fargate Service + ALB`
- 목표: `Backend API -> SQS -> EventBridge Pipe -> ECS RunTask(Fargate) -> Backend Result API -> DB`

### 2.2 백엔드 서버
- 기존: 상시 `EC2 + ASG(min=1) + ALB`
- 목표: `API Gateway + Lambda (+ 필요 시 SQS)`

## 3. Terraform 모듈
- 스크래핑 비동기: `modules/scraper_async`
  - 구성: SQS, DLQ, EventBridge Pipe, Pipe IAM Role
- 백엔드 서버리스: `modules/backend_serverless`
  - 구성: Lambda, API Gateway HTTP API, 선택적 SQS/DLQ, Provisioned Concurrency

기본값은 모두 비활성:
- `enable_scraper_async = false`
- `enable_backend_serverless = false`

## 4. 1단계: 스크래핑 서버 전환 절차
### 4.1 개발 환경
1. `tfvars/develop.tfvars`에 스크래핑 비동기 변수 입력
2. `enable_scraper_async = true`
3. `terraform plan -var-file="tfvars/develop.tfvars"`
4. `terraform apply -var-file="tfvars/develop.tfvars"`
5. 백엔드에서 SQS 발행/상태조회/결과콜백 로직 검증

### 4.2 운영 환경
1. 운영값 입력 후 `enable_scraper_async = true`
2. 신규 경로 병행 배포
3. 점진 전환: `1% -> 10% -> 30% -> 50% -> 100%`
4. 단계별 게이트 통과 시 다음 단계 진행

### 4.3 전환 게이트
- 5xx 악화 없음
- 작업 성공률 99% 이상
- DLQ 급증 없음
- p95 처리시간 목표 충족
- 위반 시 5분 내 롤백

### 4.4 롤백
- 트래픽 가중치 0%로 즉시 복귀
- 기존 동기 경로 100% 복구
- 신규 리소스는 유지한 채 원인 분석 후 재시도

## 5. 2단계: 백엔드 서버 전환 절차
### 5.1 착수 조건
- 스크래핑 비동기 경로 100% 전환 후 48시간 안정화 완료
- 운영 런북/알람 체계 정비 완료

### 5.2 개발 환경
1. `backend_serverless` 객체에 `lambda_package_path` 등 필수값 채움
2. `enable_backend_serverless = true`
3. `terraform plan/apply` 수행
4. 기존 API 계약 호환 테스트

### 5.3 운영 환경
- 병행 배포 후 동일 점진 전환
- 게이트 충족 시 100% 전환
- 48시간 안정화 후 기존 EC2/ASG/ALB 제거

## 6. 검증 체크리스트
1. 정상/실패/재시도/중복처리
2. 워커 중단/재처리/DLQ 복구
3. p95 응답 및 처리시간
4. 비용 전/후 비교
