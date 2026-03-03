# 마이그레이션 런북 (develop-shadow 선검증)

## 1. 목적
- 스크래핑 서버를 먼저 완전 비동기 구조로 전환한다.
- 운영 계정 내부에 `develop-shadow-*` 접두어로 병행 인프라를 구축한다.
- 안정화 후 백엔드 서버리스 전환을 시작한다.

## 2. 고정 결정
- 리전: `ap-northeast-2`
- 상태 분리: `backend/backend-develop-shadow.hcl` (`terraform/develop-shadow/terraform.tfstate`)
- 레지스트리: 스크래핑 워커 `ECR 신규 생성`
- 워커 스펙: `Fargate 1 vCPU / 2GB` (TaskDefinition에서 설정)
- 전환 방식: 백엔드 feature flag 카나리
- 콜백 인증: HMAC

## 3. 스크래핑 1단계 배포 절차
1. 기준선 측정값 기록
- 요청량, 성공률, 5xx, p95, 월 비용을 `docs/migration-context.md` 실행 로그에 기록

2. Terraform 초기화(상태 key 분리)
```bash
terraform init \
  -backend-config=backend/backend-develop-shadow.hcl \
  -reconfigure
```

3. `tfvars/develop-shadow.tfvars` 값 채우기
- `enable_scraper_async=true`
- `scraper_async.ecs_cluster_arn`
- `scraper_async.ecs_task_definition_arn`
- `scraper_async.ecs_task_role_arns`
- `scraper_async.subnet_ids`
- `scraper_async.security_group_ids`
- `scraper_async.name_prefix=develop-shadow-scraper`

4. Plan/Apply
```bash
terraform plan -var-file=tfvars/develop-shadow.tfvars
terraform apply -var-file=tfvars/develop-shadow.tfvars
```

5. 워커 이미지 준비/배포
- 생성된 ECR URL 확인: `terraform output scraper_worker_ecr_repository_url`
- 이미지 태그: `develop-shadow-<git-sha>`
- push 후 TaskDefinition의 이미지 URI 갱신

6. 기능 검증
- 정상/포털 장애/중복 메시지/visibility timeout/DLQ 재처리
- HMAC 콜백 검증

7. 카나리 전환
- `1% -> 10% -> 30% -> 50% -> 100%`
- 단계별 30~120분 관측 후 승급

8. 안정화/정리
- 100% 전환 후 48시간 관측
- 문제 없으면 기존 상시 스크래핑 ALB/Service 제거

## 4. 게이트/중단 기준
- 성공률 `>= 99%`
- 5xx 기준선 대비 악화 없음
- p95 기준선 대비 합의 임계치 초과 없음
- DLQ 급증 없음
- 위반 시 5분 내 롤백

## 5. 백엔드 2단계 착수 조건
- 스크래핑 100% 전환 + 48시간 안정화 완료
- 운영 런북/알람/롤백 리허설 완료
