# DB Backup S3 Bucket Context

- Status: in-progress.
- Date: 2026-08-21.
- Related issue: cchaksa/cchaksa-backend#308.
- Related backend PR: cchaksa/cchaksa-backend#323.

## 배경

강의평가 기능 이후 서비스에서 생성되는 원천 데이터를 보호하기 위해 Supabase PostgreSQL logical backup이 필요하다. 백엔드 PR은 GitHub Actions에서 백업 파일을 생성하지만, 저장 대상인 prod 전용 S3 버킷은 Terraform에서 관리해야 한다.

## 범위

- prod 환경에서만 DB backup 전용 S3 버킷을 생성한다.
- Public Access Block, BucketOwnerEnforced, versioning, SSE-S3, lifecycle을 설정한다.
- root output으로 bucket name과 ARN을 제공한다.

## As-Is

- prod Terraform에는 Lambda artifact와 ALB access log용 S3 버킷은 있지만 DB backup 전용 버킷은 없다.
- backend PR #323은 `PROD_BACKUP_S3_BUCKET` GitHub Variable과 OIDC IAM Role을 전제로 한다.

## To-Be

- `modules/database_backup`은 prod에서만 `cck-prod-db-backup-<account-id>-<region>` 버킷을 만든다.
- `supabase-db/daily/`은 30일, `supabase-db/monthly/`는 365일 후 만료한다.
- `supabase-db/latest/`의 현재 객체는 보존하고, 덮어쓰기로 생기는 이전 version만 30일 후 만료한다.
- 미완료 multipart upload는 7일 후 정리한다.

## 구현 계획

1. 새 database_backup 모듈에 bucket 보안 설정과 lifecycle을 정의한다.
2. root에서 `environment == "prod"`일 때만 모듈을 생성한다.
3. output을 추가해 GitHub `PROD_BACKUP_S3_BUCKET` Variable 설정에 사용할 이름을 제공한다.
4. Terraform format과 validate를 실행하고 prod plan에서 신규 S3 리소스만 생성되는지 확인한다.

## 실행 로그

- 2026-08-21: `develop` 기반 `feat/308` worktree를 생성했다.
- 2026-08-21: S3 bucket module, root 연결, output을 추가했다.

## 검증 결과

- `terraform fmt -recursive`: 통과.
- `terraform fmt -check -recursive`: 통과.
- `git diff --check`: 통과.
- `terraform init -backend=false`: 미통과. HashiCorp provider checksum 서버 응답이 시간 초과되어 AWS provider `v5.100.0` 설치에 실패했다.
- `terraform validate`: provider 초기화 실패로 실행하지 못했다.
- prod `terraform plan`: provider 초기화 실패 및 운영 AWS 상태 조회가 필요한 작업이므로 실행하지 못했다. Terraform GitHub Actions 또는 운영자 AWS 환경에서 확인한다.

## 전환 계획

1. Terraform PR merge 후 prod Terraform Apply를 수동 실행한다.
2. `database_backup_bucket_name` output 값을 backend repository의 `prod` Environment `PROD_BACKUP_S3_BUCKET` Variable에 설정한다.
3. 사용자가 OIDC IAM Role과 Supabase/GPG Secrets를 설정한 뒤 backend backup workflow를 수동 실행한다.

## 롤백 계획

- backend workflow를 실행하기 전에는 Terraform PR을 revert한다.
- backup 객체가 생성된 뒤에는 bucket을 즉시 삭제하지 않는다. Lifecycle로 만료시키거나 별도 승인된 데이터 삭제 절차를 사용한다.

## 오픈 이슈

- GitHub OIDC provider와 prod backup IAM Role은 사용자가 별도로 구성한다.
- GitHub `prod` Environment의 Supabase Session Pooler URL과 GPG passphrase는 사용자가 별도로 설정한다.
