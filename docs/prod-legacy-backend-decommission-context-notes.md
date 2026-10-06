# prod legacy backend decommission context notes

- 2026-05-13 KST: prod API DNS는 API Gateway custom domain `d-dom0cpkh9d.execute-api.ap-northeast-2.amazonaws.com`을 바라보고 있다.
- 2026-05-13 KST: 기존 백엔드 상시 구조로 `prod-app-asg`, `prod-alb`, EC2 `i-0c7b2f59be4d8399c`가 남아 있음을 확인했다.
- 2026-05-13 KST: prod scraper async는 `prod-scraper-cluster`, `prod-scraper-jobs`, `prod-scraper-jobs-to-ecs`를 사용하므로 삭제 대상이 아니다.
- 2026-05-13 KST: `module.component[0]` 전체를 제거하면 VPC/Subnet/ACM까지 같이 삭제될 수 있어 위험하다.
- 2026-05-13 KST: API Gateway custom domain `api.cchaksa.com`은 `module.component[0].aws_acm_certificate.app`의 인증서를 사용 중이므로 ACM은 유지한다.
- 2026-05-13 KST: prod scraper RunTask는 `prod-public-a`, `prod-public-c`, `prod-app-sg`를 사용 중이므로 네트워크 계층은 유지한다.
- 2026-05-13 12:44 KST: `terraform validate` 성공.
- 2026-05-13 12:44 KST: prod plan은 `0 to add, 1 to change, 20 to destroy`로 수렴했다.
- 2026-05-13 12:44 KST: 의도하지 않은 `prod-scraper-worker` task definition replacement가 처음 plan에 섞여 `container_definitions` drift를 ignore하도록 조정했다.
- 2026-05-13 12:44 KST: ALB access log bucket에 versioned object 28,172개가 있어 Terraform destroy 전에 삭제했다.
- 2026-05-13 12:44 KST: 첫 apply는 대부분 완료됐으나, 직접 revoke한 `prod-app-sg`의 ALB 참조 ingress rule을 Terraform이 다시 삭제하려 하며 `InvalidPermission.NotFound`가 발생했다.
- 2026-05-13 12:44 KST: 이후 `terraform plan -var-file=tfvars/prod.tfvars` 재실행 결과 `No changes`로 최종 수렴했다.
