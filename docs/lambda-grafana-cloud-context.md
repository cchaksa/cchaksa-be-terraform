# lambda-grafana-cloud-context.md

- status: applied
- updated_at: 2026-03-29 Asia/Seoul

## 배경
- 기존 EC2 환경에는 Grafana 기반 모니터링이 적용되어 있으나, `modules/backend_serverless`로 배포되는 Lambda에는 Grafana Cloud 연결 구성이 없었다.
- develop-shadow Lambda도 shadow 검증 구간에서 동일한 관측 경로를 확보해야 한다.

## 범위
- 포함:
  - `modules/backend_serverless`에 Grafana Cloud Lambda extension layer/env/IAM/tracing 설정 추가
  - 루트 `backend_serverless` 입력 객체에 `grafana_cloud` 설정 추가
  - `tfvars/develop-shadow.tfvars` shadow 실값 반영
  - `AGENTS.md` 갱신
- 제외:
  - Lambda 애플리케이션 코드 변경

## As-Is
- Lambda 서버리스 모듈은 API Gateway, Lambda, optional async queue만 관리했다.
- Grafana Cloud observability layer, OTLP endpoint/env, Grafana API key secret 권한, X-Ray active tracing 설정이 없었다.
- `develop-shadow` tfvars에는 Grafana Cloud 관련 입력이 없었다.

## To-Be
- Lambda에 Grafana Cloud collector extension layer를 연결할 수 있다.
- `backend_serverless.grafana_cloud.enabled=true`일 때 Grafana Cloud env와 Secrets Manager 읽기 권한, X-Ray write 권한, active tracing이 함께 활성화된다.
- Lambda 애플리케이션이 OTLP localhost collector(`http://localhost:4318`)로 trace/metric/log를 밀어 넣을 수 있는 기본 env가 준비된다.
- develop-shadow shadow 환경은 새 Grafana Cloud stack과 Secrets Manager secret으로 바로 연결할 수 있다.

## 구현 계획
- 루트 변수와 모듈 변수에 `grafana_cloud` 객체를 추가한다.
- 모듈에서 Grafana Cloud 활성화 시 layer/env/IAM/tracing을 조건부 생성한다.
- `develop-shadow` 실환경에는 stack/OTLP endpoint/secret ARN을 채우고 shadow 전용 sampling/metrics export env를 함께 넣는다.
- 문서와 AGENTS 규칙을 이번 입력 구조 기준으로 동기화한다.

## 실행 로그
- 2026-03-28 Asia/Seoul / local
  - `component`와 `modules/backend_serverless` 코드를 점검해 기존 EC2 Grafana 설정은 저장소 내에 없고 Lambda Grafana 지원도 부재함을 확인했다.
  - Grafana 공식 Lambda extension 문서/README와 Spring Boot tracing 문서를 확인해 extension layer + `GRAFANA_CLOUD_*` env + Secrets Manager 권한 패턴으로 구현 방향을 확정했다.
  - `modules/backend_serverless`에 Grafana Cloud conditional 설정을 추가했다.
  - 새 Grafana Cloud stack `developshadowcchaksa`를 `prod-ap-northeast-0 (Japan)`에 생성했다.
  - stack-scoped access policy/token을 만들고 AWS Secrets Manager `develop-shadow/backend/GRAFANA_CLOUD_INGEST_TOKEN`에 저장했다.
  - OTLP gateway 인증 테스트로 Lambda extension용 `GRAFANA_CLOUD_INSTANCE_ID=1575247`를 검증했다.
  - `variables.tf`, `main.tf`, `tfvars/develop-shadow.tfvars`, `AGENTS.md`를 갱신했다.
  - `./gradlew test lambdaZip`로 백엔드 zip을 빌드한 뒤, shadow Lambda 새 코드 버전 `39`를 publish하고 `live` alias를 전환했다.
  - Grafana Cloud `Application Observability` 폴더의 `JVM (Micrometer)`, `Spring Boot 3.x Statistics` 대시보드를 Lambda/OTLP sparse metric 특성에 맞게 수정했다.
  - 주요 수정은 `service_name` 변수 기준으로 라벨 정렬, Micrometer metric name 변환(`*_seconds` -> `*_milliseconds`, `jvm_threads_*_threads` -> `jvm_threads_*`), Lambda idle 구간 대응을 위한 `last_over_time(...)`, sparse counter 대응을 위한 `increase(...)` 적용이다.
  - Tomcat/File Descriptor/Process Memory 기반 패널은 Lambda에서 메트릭이 없으므로 `Request Activity`, `JVM Buffer Memory`, `JDBC Connections`, `JDBC Active Connections`로 대체했다.
  - `Loki Logs` 대시보드는 기본 생성된 `New Panel` 제목을 `develop-shadow-api Logs`로 정리하고, 빈 문자열 필터를 제거해 기본 로그 조회 패널로 고정했다.
  - Grafana Cloud stack에 CloudWatch datasource `aws-cloudwatch-prod-cchaksa`를 추가하고 health check(`metrics API`, `logs API`) 성공을 확인했다.
  - `AWS EC2`, `AWS Application Load Balancer`, `AWS ECS Cluster` 대시보드에 CloudWatch datasource와 기본 리소스 선택값을 반영했다.
  - `AWS Infrastructure` 폴더에 `AWS Serverless Operations` 대시보드를 추가해 Lambda, API Gateway, SQS, DLQ 패널을 구성했다.
  - CloudWatch datasource를 정적 access key 방식에서 `Grafana Assume Role` 방식으로 전환했다.
  - Grafana Cloud CloudWatch datasource가 요구하는 account ID `008923505280`, external ID `1575247`를 기준으로 AWS IAM role `develop-shadow-grafana-cloudwatch-read`를 생성했다.
  - role trust policy에는 `arn:aws:iam::008923505280:root`와 `sts:ExternalId=1575247`를 적용했다.
  - role inline policy에는 Grafana 공식 CloudWatch metrics/logs 예제 권한(`cloudwatch:* read`, `logs:* query read`, `ec2:Describe*`, `tag:GetResources`, `pi:GetResourceMetrics`)을 반영했다.
  - CloudWatch datasource `aws-cloudwatch-prod-cchaksa`를 `authType=grafana_assume_role`, `assumeRoleArn=arn:aws:iam::984762359128:role/develop-shadow-grafana-cloudwatch-read`로 갱신하고 저장된 access key/secret key를 제거했다.
  - `AWS EC2` 대시보드의 인스턴스 레벨 Disk/Burst 패널은 실제 데이터가 없는 EC2 namespace 대신 EBS volume 메트릭(`VolumeReadOps`, `VolumeWriteOps`, `VolumeReadBytes`, `VolumeWriteBytes`, `VolumeIdleTime`)으로 대체했다. `gp3`에서 제공되지 않는 `BurstBalance`, `VolumeThroughputPercentage`는 안내용 text 패널로 전환했다.
  - `AWS Application Load Balancer` 대시보드의 `RuleEvaluations`, `ELBAuth*`, `IPv6ProcessedBytes` 패널은 현재 ALB 구성에서 메트릭이 생성되지 않아 `ClientTLSNegotiationErrorCount`, `NewConnectionCount`, `ProcessedBytes`, 안내용 text 패널로 재구성했다.
  - `AWS ECS Cluster` 대시보드는 현재 RunTask 구조에서 `AWS/ECS` namespace 메트릭이 비어 있으므로 `AWS ECS RunTask Signals`로 재구성하고, SQS/DLQ/Trigger Lambda 지표 위주 패널로 대체했다.
  - 대시보드 보정에 사용한 임시 Grafana Cloud bootstrap access policy `210167e6-e410-47d6-8343-1db0a1c5ceb8`와 stack service account `20`은 작업 종료 후 삭제했다.
  - 이후 `JVM (Micrometer)` 대시보드에서 `JVM Memory`, `JVM Memory Pools (Heap/Non-Heap)`, `Buffer Pools`, `JVM Misc` 일부가 여전히 비는 문제를 추가 점검했다.
  - Prometheus 직접 조회 결과 raw gauge instant query는 빈 벡터를 반환하지만 `last_over_time(...[24h])` 기준으로는 heap/nonheap/buffer/thread/cpu/load 값이 존재함을 확인했다.
  - 원인은 Lambda idle 구간에서 gauge 샘플이 끊기는데, 해당 패널들이 raw metric 또는 짧은 현재 시점 평가를 사용하고 있었기 때문이다.
  - stack service account token을 사용해 `jvm-micrometer-4701` version `5`를 저장했고, 메모리/메모리 풀/버퍼/스레드/CPU/Load 패널을 `last_over_time(...[24h])` 기반으로 수정했다.
  - heap/nonheap 반복 패널에는 `area` 필터를 명시해 pool 라벨 선택과 쿼리 범위를 일치시켰다.

## 검증 결과
- 2026-03-28 Asia/Seoul / local
  - `terraform fmt -recursive`: 통과
  - `terraform validate`: 통과
  - `terraform plan -var-file=tfvars/develop-shadow.tfvars`: Lambda layer/env/IAM/X-Ray만 변경 확인, EC2/ASG 변경 없음
  - `terraform apply -auto-approve -var-file=tfvars/develop-shadow.tfvars`: 통과
  - `aws lambda get-function-configuration`: Grafana layer/env, Active tracing 반영 확인
  - `curl https://12eoa1iy3h.execute-api.ap-northeast-2.amazonaws.com/health`: 200 확인
  - `curl https://dev.api.cchaksa.com/health`: 일시적 500 발생 후 재시도 시 200 확인
  - `aws logs tail /aws/lambda/develop-shadow-develop-shadow-api`: extension 기동, `/health` 요청 로그, exporter error 부재 확인
  - Grafana HTTP API로 대시보드 JSON 재조회: `jvm-micrometer-4701` version `4`, `spring-boot-19004` version `4`, `pp7stsm` version `3`, `aws-ec2-617` version `3`, `aws-alb-650` version `3`, `aws-ecs-cluster-551` version `3` 반영 확인
  - Prometheus query API로 `service_name=develop-shadow-api` 기준 `last_over_time(process_uptime_milliseconds[24h])`, `last_over_time(jvm_threads_live[24h])`, `last_over_time(jdbc_connections_active[24h])`, `last_over_time(jvm_classes_loaded[24h])` 반환 확인
  - Prometheus query API로 `sum(increase(http_server_requests_milliseconds_count[6h]))`, `sum by (level) (increase(logback_events_total[6h]))`, `last_over_time(hikaricp_connections[24h])`가 빈 시계열 대신 값 또는 `0`으로 반환되는 것 확인
  - 추가 보정 후 Grafana HTTP API 재조회 기준 `jvm-micrometer-4701` version `5` 확인
  - Grafana datasource query API로 `sum(last_over_time(jvm_memory_used_bytes{area="heap"}[24h]))`, `last_over_time(jvm_memory_used_bytes{area="heap",id=~".*"}[24h])`, `sum(last_over_time(jvm_buffer_memory_used_bytes[24h]))`, `last_over_time(jvm_threads_states[24h])`, `last_over_time(process_cpu_usage[24h])`가 모두 frame을 반환하는 것 확인
  - Loki query API로 `{service_name="develop-shadow-api"}` 로그 스트림 조회 결과 존재 확인
  - CloudWatch datasource resource API로 `AWS/Lambda`, `AWS/SQS`, `AWS/ApplicationELB`, `AWS/ApiGateway` 네임스페이스/차원값 조회 성공
  - CloudWatch datasource `GET /api/datasources/uid/aws-cloudwatch-prod-cchaksa`: `authType=grafana_assume_role`, `assumeRoleArn` 반영 및 `secureJsonFields={}` 확인
  - CloudWatch datasource `GET /api/datasources/uid/aws-cloudwatch-prod-cchaksa/health`: `metrics API`, `logs API` 모두 `OK` 확인
  - CloudWatch datasource resource API로 Lambda FunctionName, ALB LoadBalancer, SQS QueueName 차원값 조회 성공
  - `aws cloudwatch get-metric-statistics`로 최근 24시간 기준 `Lambda Invocations`, `SQS ApproximateNumberOfMessagesVisible`, `API Gateway Count`, `ALB RequestCount` datapoint 존재 확인
  - `aws cloudwatch get-metric-statistics`로 최근 24시간 기준 EC2 instance-level `DiskReadOps`, `DiskWriteOps`, `DiskReadBytes`, `DiskWriteBytes`, `BurstBalance`, `VolumeThroughputPercentage`가 비어 있고, EBS volume-level `VolumeReadOps`, `VolumeWriteOps`, `VolumeReadBytes`, `VolumeWriteBytes`, `VolumeIdleTime`는 존재함을 확인
  - `aws cloudwatch list-metrics --namespace AWS/ECS --region ap-northeast-2`와 `ECS/ContainerInsights` 조회 결과 현재 RunTask 구조에 해당하는 cluster/service 지표가 없음을 확인
  - 미완료:
    - Grafana Cloud UI/API에서 traces/logs/metrics read-back 최종 확인

## 전환 계획
- `tfvars/develop-shadow.tfvars` 기준으로 Terraform plan/apply를 수행한다.
- `terraform plan -var-file=tfvars/develop-shadow.tfvars`와 shadow Lambda 로그/trace 수집 결과를 확인한다.
- Grafana Cloud stack UI에서 `develop-shadow-api` 서비스 기준 traces/logs/metrics read-back을 캡처한다.

## 롤백 계획
- `backend_serverless.grafana_cloud.enabled=false`로 되돌린 후 Terraform apply 한다.
- 필요 시 Grafana Cloud 관련 secret read 정책과 X-Ray 권한, layer 설정이 제거되는지 plan/apply 결과로 확인한다.

## 오픈 이슈
- Grafana Cloud token이 customer managed KMS key로 암호화된 secret이면 추가 `kms:Decrypt` 권한이 필요할 수 있다.
- 애플리케이션 metric export는 백엔드 저장소의 `micrometer-registry-otlp` 추가가 선행되어야 한다.
- Grafana Cloud query endpoint/label 기준이 명확하지 않아 API 기반 자동 검증은 추가 정리가 필요하다.
- Lambda idle 구간에서는 gauge/counter 계열이 sparse 하게 들어오므로 Grafana range query가 step에 따라 빈 값으로 보일 수 있다. 대시보드는 `last_over_time(...)` 또는 `increase(...)` 형태로 보정해야 한다.
- 현재 스크래핑 워커는 ECS Service가 아니라 RunTask 구조라 `AWS/ECS`, `ECS/ContainerInsights` 기반 cluster/service 패널은 구조적으로 비며, SQS/Trigger Lambda 중심 신호로 대체하는 편이 맞다.
- CloudWatch datasource 전환 후에는 더 이상 Grafana stack 내 정적 AWS access key가 저장되지 않는다. 다만 대화에 노출된 Grafana Cloud 관리 토큰은 별도로 폐기해야 한다.
