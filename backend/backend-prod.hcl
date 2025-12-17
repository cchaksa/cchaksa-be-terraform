bucket         = "prod-tfstate-679191205633" # 실제 생성된 버킷 이름
key            = "terraform/prod/terraform.tfstate"
region         = "ap-northeast-2"

use_lockfile = true
encrypt        = true

profile        = "prod-cchaksa"   # aws configure --profile prod 에서 설정한 이름