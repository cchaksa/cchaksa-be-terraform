# prod legacy backend decommission context

상태: done

## 배경
prod API 트래픽을 기존 EC2/ASG/ALB 기반 상시 백엔드에서 API Gateway + Lambda 기반 서버리스 백엔드로 전환했다. 전환 후 기존 상시 백엔드 리소스가 비용을 발생시키고 있어 삭제했다.

## 범위
이번 작업은 prod의 기존 백엔드 상시 실행 계층만 제거했다.

삭제 범위는 다음과 같다.
- `prod-app-asg`
- prod app EC2 instance `i-0c7b2f59be4d8399c`
- prod app launch template `lt-0a053508ae4271ed6`
- `prod-alb`
- HTTP/HTTPS listener
- `prod-app-tg`
- EC2 전용 IAM role/profile/policy
- EC2 전용 CloudWatch log group
- ALB access log bucket `prod-alb-access-logs-984762359128-ap-northeast-2`

유지 범위는 다음과 같다.
- API Gateway custom domain과 backend Lambda
- EventBridge Scheduler maintenance 리소스
- prod scraper SQS/Pipe/ECS RunTask 리소스
- scrape result S3 bucket
- VPC/Subnet/Route Table/Internet Gateway
- scraper RunTask가 사용하는 security group
- API Gateway custom domain이 사용하는 ACM certificate

## As-Is
prod Terraform state에는 `module.component[0]` 아래에 EC2/ASG/ALB와 VPC/Subnet/SG/ACM이 함께 관리되고 있었다. 단순히 `module.component[0]` 전체를 비활성화하면 새 서버리스 운영 경로가 사용하는 공유 리소스까지 삭제될 수 있었다.

## To-Be
`module.component[0]`는 유지하되, legacy app stack만 별도 flag로 비활성화했다. 네트워크/ACM 등 공유 리소스는 유지했다.

## 구현 계획
1. component 모듈에 legacy app stack 활성화 플래그를 추가한다.
2. EC2/ASG/ALB/IAM/로그/ALB log bucket 리소스에 조건부 count를 적용한다.
3. app security group은 유지하되 ALB security group 참조 ingress는 legacy stack 활성화 시에만 만든다.
4. prod tfvars에서 legacy app stack을 비활성화한다.
5. plan에서 destroy 대상이 legacy app stack에 한정되는지 확인한다.
6. apply 후 AWS 실 리소스 상태를 확인한다.

## 실행 로그
- 2026-05-13 KST: 작업 시작.
- 2026-05-13 KST: `enable_legacy_backend_stack` 루트 변수를 추가했다.
- 2026-05-13 KST: `component.enable_app_stack`으로 EC2/ASG/ALB 계층만 조건부 생성되도록 변경했다.
- 2026-05-13 KST: prod에서 `enable_legacy_backend_stack=false`로 설정했다.
- 2026-05-13 KST: `terraform validate` 성공.
- 2026-05-13 KST: 최초 plan에 `prod-scraper-worker` task definition replacement가 섞여 있어 CI 관리 대상 drift를 `ignore_changes = [container_definitions]`로 제외했다.
- 2026-05-13 KST: 최종 plan은 `0 to add, 1 to change, 20 to destroy`였다.
- 2026-05-13 KST: ALB access log bucket의 versioned object 28,172개를 삭제했다.
- 2026-05-13 KST: `terraform apply /tmp/prod-legacy-backend-decommission.tfplan` 실행.
- 2026-05-13 KST: apply 중 `prod-app-sg`의 ALB 참조 ingress rule을 직접 revoke했고, 이로 인해 마지막 SG update에서 `InvalidPermission.NotFound`가 발생했다.
- 2026-05-13 KST: 재실행한 `terraform plan -var-file=tfvars/prod.tfvars`에서 `No changes`를 확인했다.

## 검증 결과
- `prod-app-asg`: `describe-auto-scaling-groups` 결과 `[]`.
- `prod-alb`: `LoadBalancerNotFound`.
- `prod-app-tg`: `TargetGroupNotFound`.
- `i-0c7b2f59be4d8399c`: `terminated`.
- `prod-ec2-role`: `NoSuchEntity`.
- `prod-ec2-profile`: `NoSuchEntity`.
- `prod-ec2-lifecycle-hook` policy: `NoSuchEntity`.
- `prod-alb-access-logs-984762359128-ap-northeast-2`: `HeadBucket 404 Not Found`.
- `/prod/ec2/*` log groups: `[]`.
- `https://api.cchaksa.com/health`: `HTTP/2 200`.
- `prod-haksa-api`: Lambda `Active`, `LastUpdateStatus=Successful`.
- `prod-scraper-jobs`, `prod-scraper-jobs-dlq`: 유지 확인.
- `prod-scraper-jobs-to-ecs`: Pipe `RUNNING`.

## 전환 계획
prod API DNS는 API Gateway custom domain으로 전환되어 있으며, legacy backend stack 삭제 후에도 API Gateway/Lambda 경로가 정상 응답했다.

## 롤백 계획
문제 발생 시 `enable_legacy_backend_stack=true`로 되돌리고 Terraform apply를 수행해 legacy ASG/ALB 계층을 재생성한다. 단, EC2 AMI와 user-data 기반 복구가 필요하므로 즉시 롤백보다는 Lambda/API Gateway 경로 확인을 우선한다.

## 오픈 이슈
- prod scraper RunTask가 아직 `prod-app-sg`를 사용 중이다. legacy backend 삭제 후 별도 scraper 전용 security group으로 분리하는 후속 작업이 필요하다.
- `prod-app-sg`에는 기존 SSH/Redis ingress가 남아 있다. scraper 전용 SG 분리 시 제거해야 한다.
