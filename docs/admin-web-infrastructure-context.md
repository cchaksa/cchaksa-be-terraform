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
- 기존 GitHub Actions static key 인증을 우선 사용한다. 환경별 입력이 명시된 경우에만 Terraform이 해당 환경의 최소 배포 policy를 기존 IAM user에 연결한다.
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
- dev state key는 `terraform/admin-web/dev/terraform.tfstate`다. 최초 적용 전 add-only plan과 기존 prod state 무변경을 다시 확인한다.
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

1. Prod와 dev의 ACM 검증 CNAME 및 service CNAME 등록은 완료됐다.
2. Prod와 dev 모두 CloudFront를 통한 `/api/admin/*` JSON 오류 전달을 확인했다.
3. FE/BE 배포 스레드에서 SPA object와 로컬 관리자 인증 서버를 배포한다.
4. 로컬 관리자 계정으로 dev/prod 로그인, 문의 조회와 답변 등록 E2E를 검증한다.

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
- 당시 Cloudflare 세션이 로그인되지 않아 prod service CNAME 등록과 운영 도메인 검증을 일시 중단했다.

Prod DNS 후속 검증:

- 사용자가 `admin.cchaksa.com` service CNAME을 Cloudflare `DNS only`로 등록했다.
- 권한 DNS와 public resolver에서 동일 CloudFront target, TTL 300과 정상 TLS를 확인했다.
- `/api/admin/auth/me`는 CloudFront를 통해 `401 application/json`을 반환해 API 오류가 SPA HTML로 치환되지 않음을 확인했다.
- `/`는 `403 AmazonS3`를 반환했다. CloudFront routing은 정상이며 SPA object는 아직 배포되지 않았다.

## 2026-10-01 dev bootstrap 적용 기록

- dev backend key를 `terraform/admin-web/dev/terraform.tfstate`로 분리하고 `environment=dev`, `dev.admin.cchaksa.com`, `dev.api.cchaksa.com` 전용 입력을 추가했다.
- 적용 전 dev state key가 비어 있고 기존 prod state 주소가 유지됨을 확인했다.
- bootstrap saved plan은 `9 add / 0 change / 0 destroy`였고 create 대상이 모두 dev 이름과 tag를 사용하는지 JSON으로 검토했다.
- private S3와 보호 설정, `us-east-1` ACM 요청, dev OAC, SPA rewrite Function, dev 배포 IAM policy를 적용했다.
- apply 결과는 `9 added / 0 changed / 0 destroyed`였고 post-apply plan은 `No changes`였다.
- dev ACM은 `PENDING_VALIDATION`이며 Cloudflare에 다음 CNAME을 `DNS only`로 등록해야 한다.
  - Name: `_8282fa83b79d39705aba28fb8a3a5ee7.dev.admin.cchaksa.com`.
  - Type: `CNAME`.
  - Target: `_17b392618952a2f32fda8ea0dc1ac2b1.wzccmgtwzk.acm-validations.aws`.
- Cloudflare 세션이 로그인되지 않아 검증 CNAME 등록 전 중단했다. dev CloudFront plan/apply는 인증서 `ISSUED` 전까지 수행하지 않는다.

Dev 인증서 및 CloudFront 후속:

- 사용자가 dev ACM 검증 CNAME을 Cloudflare `DNS only`로 등록했고 public resolver에서 exact target을 확인했다. 검증 레코드는 자동 갱신을 위해 유지한다.
- ACM을 60초 간격으로 polling해 약 4분 뒤 `ISSUED`를 확인했다.
- dev CloudFront saved plan은 `2 add / 1 change / 0 destroy`였다. 변경 주소는 dev distribution 생성, dev S3 bucket policy 생성, dev 배포 policy에 distribution invalidation 권한 추가뿐이었다.
- saved plan 적용 결과는 `2 added / 1 changed / 0 destroyed`였다.
- dev CloudFront는 `Deployed` 상태이며 `dev.admin.cchaksa.com` alias, private dev S3 origin, `dev.api.cchaksa.com`의 `/api/admin/*` behavior와 dev SPA rewrite Function 연결을 확인했다.
- dev CloudFront service CNAME target은 `d14a6typxgzidb.cloudfront.net`이다.
- apply 후 dev와 prod plan 모두 `No changes`였다.
- 당시 Cloudflare 세션이 로그인되지 않아 `dev.admin.cchaksa.com` service CNAME 등록 전 일시 중단했다.

## 2026-10-02 dev DNS 검증 및 인프라 완료

- 사용자가 `dev.admin.cchaksa.com`을 `d14a6typxgzidb.cloudfront.net`으로 연결하는 service CNAME을 Cloudflare `DNS only`로 등록했다.
- Cloudflare 권한 DNS, `1.1.1.1`, `8.8.8.8`에서 동일 target을 확인했고 TLS도 정상이다.
- `GET /api/admin/auth/me`는 CloudFront를 통해 `401 application/json`을 반환해 API 오류가 SPA fallback으로 치환되지 않음을 확인했다.
- `GET /`는 CloudFront를 통해 `403 AmazonS3`를 반환했다. DNS, TLS와 routing은 정상이며 SPA object가 아직 배포되지 않은 상태다.
- 마지막 확인 기준 dev와 prod Terraform plan은 모두 `No changes`다. 이번 단계에서는 추가 AWS apply를 수행하지 않았다.
- 관리자 인프라 구축은 완료됐으며 후속 SPA·서버 배포와 로그인 E2E는 FE/BE 스레드에서 조정한다.

## 2026-10-02 dev 배포 IAM plan

- 최근 dev Lambda 배포 CloudTrail 이벤트의 principal은 `backend-lambda-github-actions` IAM user다.
- 이 user에는 Lambda 배포 inline policy와 prod 관리자 웹 배포 managed policy가 연결돼 있지만 dev 관리자 웹 배포 policy는 연결돼 있지 않았다.
- `deploy_iam_user_name`이 설정된 환경에만 해당 환경의 `admin_web_deploy` policy를 연결하는 조건부 attachment를 추가했다.
- dev 입력만 `backend-lambda-github-actions`를 지정하며 prod 입력은 unset 상태를 유지한다.
- dev policy 범위는 dev 관리자 S3 bucket의 list/object read-write-delete와 dev CloudFront distribution invalidation뿐이다. prod bucket/distribution 권한은 이 policy에 포함되지 않는다.
- dev saved plan은 `1 add / 0 change / 0 destroy`이며 유일한 변경 주소는 `aws_iam_user_policy_attachment.admin_web_deploy[0]`이다.
- prod preservation plan은 `No changes`다.
- 이번 단계에서는 saved plan을 적용하지 않았다.
