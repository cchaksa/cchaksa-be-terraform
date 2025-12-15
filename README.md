# 척척학사 Terraform Infrastructure

**AWS 인프라를 Terraform으로 관리**하고,  
**GitHub Actions와 Discord 명령어를 통해 인프라를 제어**하는 것을 목표로 합니다.

Develop(개발) 환경과 Production 환경을 분리하여 운영하며,  
Terraform Plan / Apply를 GitHub Actions로 자동화하여  
**안전한 변경 검증 → 수동 승인 적용** 흐름을 구성했습니다.

---

## 🎯 주요 기능

- **Discord Bot**
    - Develop 인프라 시작 / 종료 / 상태 확인
- **AWS Infrastructure**
    - EC2, RDS 등 서비스 운영 인프라 관리
- **Terraform IaC**
    - 코드 기반 인프라 관리
- **GitHub Actions**
    - PR 시 Terraform Plan 자동 실행
    - 승인 후 Terraform Apply 수동 실행
- **환경 분리**
    - Develop / Production 독립 운영
- **비용 절감**
    - Develop 환경은 필요 시에만 운영

---

## 📚 문서

- **[SETUP.md](./SETUP.md)**  
  로컬 개발 환경 및 Terraform 실행 방법 정리

---

## 🚀 인프라 제어 방식 개요

### 1️⃣ Develop 인프라 (개발 환경)

#### Discord 명령어
```
/infra start    # Develop 인프라 시작
/infra stop     # Develop 인프라 종료
/infra status   # 상태 확인
```

- Develop 환경은 비용 절감을 위해 **필요한 시간에만 운영**
- Discord Bot은 Develop 환경 전용

---

### 2️⃣ Terraform + GitHub Actions (권장 방식)

#### Terraform Plan
- `develop` 브랜치를 기준으로 PR 생성 시 자동 실행
- 변경 사항을 **실제 리소스 생성 없이 검증**
- Plan 결과는 PR 코멘트로 확인 가능

#### Terraform Apply
- GitHub Actions `workflow_dispatch`로 **수동 실행**
- GitHub Environment를 통한 승인 후 적용 가능
- Develop / Production 각각 독립 실행

---

## 🧪 Terraform 변경 테스트 흐름 (Develop 기준)

1. `develop` 브랜치 기준으로 작업 브랜치 생성
2. Terraform 코드 변경
3. `develop` 브랜치로 PR 생성
4. GitHub Actions에서 Terraform Plan 자동 실행
5. Plan 결과 확인
6. PR 머지
7. 필요 시 GitHub Actions에서 Terraform Apply 수동 실행

> Develop에서는 `null_resource` 등을 활용해  
> **실제 AWS 리소스 생성 없이 apply 테스트**를 수행할 수 있습니다.

---

## 💻 로컬에서 Terraform 실행

### AWS CLI 자격 증명 설정

Terraform 실행을 위해 AWS Profile 기반 인증을 사용합니다.

#### 자격 증명 파일 위치
- **Windows**
  ```
  C:\Users\<사용자명>\.aws\credentials
  ```
- **macOS**
  ```
  /Users/<사용자명>/.aws/credentials
  ```

#### 예시
```
[develop]
aws_access_key_id     = <ACCESS_KEY>
aws_secret_access_key = <SECRET_KEY>

[prod]
aws_access_key_id     = <ACCESS_KEY>
aws_secret_access_key = <SECRET_KEY>
```

---

### Terraform 초기화

환경 변경 시마다 `terraform init`을 다시 실행해야 합니다.

```shell
# Develop
terraform init \
-var-file="tfvars/develop.tfvars" \
-backend-config="backend-develop.hcl" \
-reconfigure

# Production
terraform init \
-var-file="tfvars/prod.tfvars" \
-backend-config="backend-prod.hcl" \
-reconfigure
```

---

### Terraform 실행

#### 실행 계획 확인
```shell
# Develop
terraform plan -var-file="tfvars/develop.tfvars"

# Production
terraform plan -var-file="tfvars/prod.tfvars"
```

#### 실제 적용
```shell
# Develop
terraform apply -var-file="tfvars/develop.tfvars"

# Production
terraform apply -var-file="tfvars/prod.tfvars"
```

---

## 🧹 코드 포맷팅

```shell
terraform fmt --recursive
```