# prod legacy backend decommission checklist

- [x] 현재 prod 전환 상태 확인
- [x] legacy backend 삭제 범위 확정
- [x] Terraform에서 legacy app stack 비활성화 플래그 추가
- [x] prod tfvars에서 legacy app stack 비활성화
- [x] `terraform fmt` 실행
- [x] `terraform validate` 실행
- [x] `terraform plan -var-file=tfvars/prod.tfvars`로 삭제 대상 검증
- [x] ALB access log bucket versioned objects 정리
- [x] `terraform apply /tmp/prod-legacy-backend-decommission.tfplan` 실행
- [x] 부분 apply 후 reconcile plan으로 `No changes` 확인
- [x] AWS에서 ASG/ALB/EC2 삭제 확인
- [x] API Gateway/Lambda/SQS/Pipe 유지 확인
- [x] 변경 사항 커밋 및 push
