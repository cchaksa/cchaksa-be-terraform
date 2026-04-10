# scrape-result-storage-context.md

- status: in-progress
- updated_at: 2026-04-09 Asia/Seoul

## 배경
- 스크래핑 워커 결과를 백엔드 API로 직접 push 하던 구조에서 S3 결과물을 전달하고 Lambda는 key만 받아 후처리해야 한다.
- develop-shadow 환경에서만 병행으로 S3 버킷을 생성하고 운영 영향 없이 결과 저장 경로를 검증해야 한다.

## 범위
- 루트 모듈에 `scrape_result_storage` 입력/로컬/리소스를 추가해 결과 버킷과 IAM/ENV를 자동 관리.
- develop-shadow tfvars에 신규 객체를 선언하고 기본 prefix(`develop-shadow/`)를 고정.
- 워커/Lambda IAM과 환경변수 자동 주입, 30일 lifecycle 적용.
- AGENTS.md, context 문서 보강 및 검증(cmd 기반) 수행.

## As-Is
- 워커는 결과를 곧바로 백엔드에 전송하며 저장 버킷이나 IAM 권한이 정의되어 있지 않았다.
- tfvars/develop-shadow.tfvars 파일이 저장소에 없어서 환경 입력 소스가 불명확했다.
- 백엔드 Lambda/Worker 환경변수에 `SCRAPE_RESULT_*` 값이 존재하지 않고 S3 접근도 불가했다.

## To-Be
- `scrape_result_storage.enabled=true` 설정 시 `cck-<env>-scrape-results-<account>` 형태 버킷이 자동 생성되며 prefix 기반 30일 lifecycle, AES256 암호화, Public Access Block이 기본 적용된다.
- 워커/Lambda IAM에 prefix 범위 제한 S3 권한이 자동 부여되고 `SCRAPE_RESULT_BUCKET`/`SCRAPE_RESULT_PREFIX` 환경변수가 자동 주입된다.
- 민감값이 필요한 실제 `tfvars/develop-shadow.tfvars`는 로컬 전용으로 유지하고, 저장소에는 `tfvars/develop-shadow.tfvars.example`만 포함한다.

## 구현 계획
1. 루트 `variables.tf`에 `scrape_result_storage` 객체 추가 및 `.gitignore` 예외 처리.
2. `main.tf`에 `aws_caller_identity`/locals/bucket/IAM 리소스와 env merge 로직 추가, 모듈 인자 업데이트.
3. `outputs.tf`, `modules/backend_serverless/outputs.tf`에 신규 출력값 추가.
4. `tfvars/develop-shadow.tfvars` 및 AGENTS.md 업데이트, 신규 context 문서 작성.
5. `terraform fmt`, `terraform validate`, `terraform plan -var-file=tfvars/develop-shadow.tfvars`로 double check.

## 실행 로그
- 2026-04-09 Asia/Seoul / local
  - 실제 apply용 `tfvars/develop-shadow.tfvars`는 로컬 전용 민감 입력으로 유지하고, PR에는 `tfvars/develop-shadow.tfvars.example`만 포함하도록 정리.
  - `variables.tf`에 `scrape_result_storage`를 정의하고 `main.tf`에 locals/버킷/IAM/ENV 파이프라인을 구현.
  - `modules/backend_serverless/outputs.tf`, 루트 `outputs.tf`를 확장하여 Lambda role 및 결과 버킷 정보를 노출.
  - `docs/scrape-result-storage-context.md` 초안을 작성하고 AGENTS.md를 갱신.
- 2026-04-10 Asia/Seoul / local
  - Lambda 현재 운영값과 무관한 drift가 plan에 포함되지 않도록 `backend_serverless.lambda_memory_size`, `backend_serverless.reserved_concurrent_executions` override 입력을 추가했다.
  - backend Lambda 환경변수는 기존 운영값에 `SCRAPE_RESULT_BUCKET`, `SCRAPE_RESULT_PREFIX`만 추가되도록 정리하고 placeholder `SUPABASE_*`, `LOGGING_LEVEL_ROOT` 입력은 제거했다.
  - `terraform apply -var-file=tfvars/develop-shadow.tfvars -auto-approve`를 실행해 develop-shadow 결과 버킷/IAM/워커 task definition/Lambda 환경변수를 반영했다.

## 검증 결과
- 2026-04-09 Asia/Seoul / local
  - `terraform fmt -recursive`
  - `terraform validate`는 초기 구현 시 성공했으나, PR 준비 중 재실행에서는 AWS provider schema handshake 오류로 실패했다. 동일 init/backend 상태에서 `terraform plan -var-file=tfvars/develop-shadow.tfvars`는 정상 완료됐다.
  - `terraform plan -var-file=tfvars/develop-shadow.tfvars`
  - `terraform apply -var-file=tfvars/develop-shadow.tfvars -auto-approve`
  - apply 후 `terraform plan -var-file=tfvars/develop-shadow.tfvars` 결과 `No changes. Your infrastructure matches the configuration.`

## 전환 계획
- develop-shadow 전용 profile로 `terraform plan/apply -var-file=tfvars/develop-shadow.tfvars`를 실행하여 결과 버킷과 IAM/ENV 만 변경되는지 검증한다.
- 백엔드/워커 애플리케이션이 `SCRAPE_RESULT_*` 환경변수를 참조하도록 코드/설정을 맞춘 후 Shadow에서 end-to-end 테스트를 수행한다.

## 롤백 계획
- `scrape_result_storage.enabled=false` 로 토글하고 Terraform apply를 수행하면 신규 S3/IAM/ENV가 제거된다.
- 필요 시 tfvars에서 객체 블록을 제거하고 AGENTS/문서를 기존 상태로 복원한다.

## 오픈 이슈
- 실제 `tfvars/develop-shadow.tfvars`는 민감값을 포함하므로 Git에 올리지 않고, PR에는 `tfvars/develop-shadow.tfvars.example`만 포함한다.
- AWS profile 자격 증명이 세팅되지 않으면 plan/validate가 실패하므로 CI/로컬 모두 공통 profile 구성이 필요하다.
- Lambda 패키지 경로(`backend/build/develop-shadow-api.zip`)는 placeholder zip이므로 백엔드 빌드 파이프라인에서 실제 artifact를 공급해야 한다.
