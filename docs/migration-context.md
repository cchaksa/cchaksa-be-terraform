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
  - `API Gateway + Lambda (+ 필요 시 SQS)`
  - 지연 민감 API는 Provisioned Concurrency(필요 시간대만), 일반 API는 경량화 중심

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
- 도메인 연결/경로 라우팅: 추가 필요(운영 라우팅 정책)

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
