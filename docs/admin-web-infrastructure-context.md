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

## 외부 작업

- Cloudflare ACM validation CNAME 등록.
- Cloudflare `admin.cchaksa.com` CNAME 등록.
- Kakao Developers에 `https://admin.cchaksa.com` 허용 도메인과 redirect URI 등록.
- 기존 GitHub Actions AWS principal에 `deploy_policy_arn` 연결.
- 실제 관리자 계정과 안전한 문의 데이터로 로그인, 조회, 답변 등록 E2E 수행.

## 2026-09-30 적용 기록

- 기존 제품 Terraform은 `develop-shadow`와 `prod` remote state를 사용하며, 어드민 state key는 적용 전 존재하지 않음을 확인했다.
- bootstrap saved plan은 `9 add / 0 change / 0 destroy`였고 해당 plan만 적용했다.
- 적용 대상은 private S3와 보호 설정, ACM 인증서 요청, CloudFront OAC와 SPA function, 어드민 배포 IAM policy다.
- 적용 직후 재계획은 `No changes`였다.
- S3 Public Access Block 네 항목이 모두 활성화된 것을 확인했다.
- CloudFront 2차 plan은 어드민 state 내부에서 `2 add / 1 change / 0 destroy`다. 1 change는 신규 배포 policy에 신규 distribution invalidation 권한을 추가하는 변경이다.
- ACM 인증서는 Cloudflare validation CNAME 등록 전이므로 `PENDING_VALIDATION`이다. 이 상태에서는 CloudFront plan을 적용하지 않는다.
- 백엔드 저장소 GitHub variable `ADMIN_WEB_S3_BUCKET`을 등록했다. distribution 생성 후 `ADMIN_WEB_CLOUDFRONT_DISTRIBUTION_ID`를 추가해야 한다.
- 운영 Lambda에는 관리자 Kakao 환경변수 이름이 아직 등록되어 있지 않다. 기존 Lambda 설정은 이 독립 state에서 변경하지 않았다.

검증 결과:

- `terraform fmt -check -recursive`: 성공.
- `terraform validate`: 성공. 로컬 sandbox의 provider handshake 제한 때문에 외부 실행으로 확인했다.
- `node tests/spa-rewrite.test.mjs`: 성공.
- bootstrap `terraform plan`: `9 add / 0 change / 0 destroy`.
- bootstrap `terraform apply`: `9 added / 0 changed / 0 destroyed`.
- post-apply `terraform plan`: `No changes`.
- CloudFront preflight `terraform plan`: `2 add / 1 change / 0 destroy`, 미적용.
