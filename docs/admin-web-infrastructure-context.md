# 관리자 웹 인프라 컨텍스트

## 배경

`cchaksa-backend#351`의 관리자 SPA는 `admin-web/dist`를 S3에 배포하고 `admin.cchaksa.com`에서 제공해야 한다. 기존 제품 Terraform root는 prod와 develop-shadow 백엔드 리소스를 관리하므로 관리자 정적 호스팅을 같은 state에 추가하면 계획과 적용의 영향 범위가 섞인다.

## 결정

- `admin-web/`을 독립 Terraform root로 두고 `terraform/admin-web/prod/terraform.tfstate` key를 사용한다.
- 기존 state bucket은 backend 저장소로만 공유하고 제품 state의 resource address는 참조하거나 import하지 않는다.
- S3는 public access를 차단하고 CloudFront OAC만 읽도록 한다.
- `/api/admin/*`는 `api.cchaksa.com` custom origin으로 전달하고 캐시를 비활성화한다.
- SPA fallback은 default S3 behavior의 CloudFront Function에서 extension이 없는 GET/HEAD URI만 `/index.html`로 rewrite한다.
- global custom error response는 사용하지 않는다. 따라서 API origin의 401, 403, 404, 5xx는 SPA HTML로 치환되지 않는다.
- Cloudflare DNS는 이 Terraform root에서 관리하지 않는다. ACM 검증 CNAME과 최종 admin CNAME은 수동으로 등록한다.
- 기존 GitHub Actions static key 인증을 우선 사용하고, Terraform은 기존 IAM principal을 수정하지 않은 채 attach 가능한 최소 배포 policy만 생성한다.
- 배포 중 기존 index가 참조하는 파일을 잃지 않도록 hash asset은 누적 보존하고 `index.html`을 마지막에 교체한다.
- 관리자 인증은 dev/prod 모두 로컬 `loginId`/password 방식을 사용한다. 관리자용 외부 OAuth/OIDC provider, redirect URI와 provider key/secret은 인프라·배포 요구사항이 아니다.
- 일반 사용자 인증은 이 관리자 인프라 root의 범위 밖이며 변경하지 않는다.

## 환경별 도메인 결정

| 환경 | 관리자 웹 도메인 | API origin | 관리자 인증 |
| --- | --- | --- | --- |
| dev | `https://dev.admin.cchaksa.com` | `dev.api.cchaksa.com` | 로컬 `loginId`/password |
| prod | `https://admin.cchaksa.com` | `api.cchaksa.com` | 로컬 `loginId`/password |

- 현재 적용된 `admin-web/` state는 prod 전용이며 그대로 보존한다.
- dev는 기존 prod resource를 재사용하거나 수정하지 않고 별도 private S3, CloudFront, `us-east-1` ACM 인증서와 state를 사용한다.
- dev state key 후보는 `terraform/admin-web/dev/terraform.tfstate`다. 실제 구현 전 add-only plan과 기존 prod state 무변경을 다시 확인한다.
- Cloudflare가 `cchaksa.com`의 권한 DNS이므로 Route 53 hosted zone은 만들거나 안내하지 않는다.

## 단계적 적용

1. `enable_distribution=false`로 S3, ACM 요청, OAC, Function, IAM policy를 add-only 적용한다.
2. ACM validation CNAME을 Cloudflare에 등록하고 인증서 `ISSUED`를 확인한다.
3. `enable_distribution=true`로 CloudFront와 S3 bucket policy를 적용한다.
4. Cloudflare에 `admin` CNAME을 DNS-only로 등록한다.
5. SPA를 배포하고 SPA route와 API 오류 응답을 각각 검증한다.

## 롤백

- SPA 배포 실패 시 S3 versioning으로 이전 `index.html`과 asset을 복원하고 CloudFront invalidation을 실행한다.
- DNS 전환 전에는 신규 CloudFront가 운영 트래픽을 받지 않는다.
- CloudFront와 S3에는 삭제 방지 설정을 두어 실수로 destroy되지 않게 한다.

## 사용자 작업과 실행 순서

1. 사용자가 Cloudflare 로그인, MFA 또는 CAPTCHA를 완료한다.
2. Codex가 `admin.cchaksa.com`을 prod CloudFront domain으로 연결하는 CNAME을 `DNS only`로 등록하고 SPA/API behavior를 검증한다.
3. Codex가 별도 dev state로 private S3와 ACM을 add-only 적용한다.
4. dev ACM 요청 뒤 사용자가 Cloudflare 로그인을 유지하면 Codex가 별도 검증 CNAME을 `DNS only`로 등록한다.
5. Codex가 dev 인증서 `ISSUED`를 확인하고 dev CloudFront를 적용한 뒤 `dev.admin.cchaksa.com` service CNAME을 `DNS only`로 등록한다.
6. 로컬 관리자 계정으로 dev/prod 로그인, 문의 조회와 답변 등록 E2E를 검증한다.

## 2026-09-30 적용 기록

- 기존 제품 Terraform은 `develop-shadow`와 `prod` remote state를 사용하며, 어드민 state key는 적용 전 존재하지 않음을 확인했다.
- bootstrap saved plan은 `9 add / 0 change / 0 destroy`였고 해당 plan만 적용했다.
- 적용 대상은 private S3와 보호 설정, ACM 인증서 요청, CloudFront OAC와 SPA function, 어드민 배포 IAM policy다.
- 적용 직후 재계획은 `No changes`였다.
- S3 Public Access Block 네 항목이 모두 활성화된 것을 확인했다.
- CloudFront 2차 preflight plan은 어드민 state 내부에서 `2 add / 1 change / 0 destroy`였다. 1 change는 신규 배포 policy에 신규 distribution invalidation 권한을 추가하는 변경이었다.
- 당시 ACM 인증서는 Cloudflare validation CNAME 등록 전이라 `PENDING_VALIDATION`이었으며 CloudFront plan을 적용하지 않았다.
- 백엔드 저장소 GitHub variable `ADMIN_WEB_S3_BUCKET`을 등록했다. distribution 생성 후 `ADMIN_WEB_CLOUDFRONT_DISTRIBUTION_ID`를 추가해야 한다.

검증 결과:

- `terraform fmt -check -recursive`: 성공.
- `terraform validate`: 성공. 로컬 sandbox의 provider handshake 제한 때문에 외부 실행으로 확인했다.
- `node tests/spa-rewrite.test.mjs`: 성공.
- bootstrap `terraform plan`: `9 add / 0 change / 0 destroy`.
- bootstrap `terraform apply`: `9 added / 0 changed / 0 destroyed`.
- post-apply `terraform plan`: `No changes`.
- CloudFront preflight `terraform plan`: `2 add / 1 change / 0 destroy`, 미적용.

## 2026-10-01 적용 및 정규화 기록

- prod ACM `ISSUED` 확인 후 CloudFront saved plan `2 add / 1 change / 0 destroy`를 적용했다.
- prod CloudFront는 `Deployed` 상태이며 `admin.cchaksa.com` alias, private S3 default origin, `api.cchaksa.com`의 `/api/admin/*` behavior와 SPA rewrite Function 연결을 확인했다.
- 최초 생성 시 잘못된 AWS 관리형 cache policy ID를 수정하고 새 saved plan을 다시 검토했다. 해당 수정은 커밋 `1febad2`에 기록했다.
- 최초 post-apply plan의 `0 add / 3 change / 0 destroy`는 OAC S3 origin에 남아 있던 빈 legacy `s3_origin_config` 블록을 provider가 state에서 제거하면서 CloudFront origin 전체가 달라 보인 결과였다.
- CloudFront가 변경으로 표시되자 distribution ARN을 참조하는 S3 bucket policy와 배포 IAM policy가 `unknown`으로 연쇄 표시됐다. 두 policy의 현재 JSON에는 의미 차이가 없었다.
- 빈 legacy 블록을 HCL에서 제거한 뒤 `terraform plan`은 `No changes`로 수렴했다. 실제 AWS drift가 아니며 후속 apply는 필요하지 않다.
- Cloudflare 세션이 로그인되지 않아 prod service CNAME 등록과 운영 도메인 검증은 대기 중이다.
