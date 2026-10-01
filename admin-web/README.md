# Admin Web Infrastructure

This Terraform root owns only the production admin SPA resources. It deliberately uses a remote state key that is separate from the product backend root.

## Ownership Boundary

- State key: `terraform/admin-web/prod/terraform.tfstate`.
- Managed resources: admin SPA S3 bucket, ACM certificate request, CloudFront OAC/function/distribution, S3 bucket policy, deployment IAM policy.
- Referenced only: the existing `api.cchaksa.com` API Gateway custom domain.
- Not managed: product Lambda/API Gateway, product state, Cloudflare DNS, application authentication data, secret values.

Admin authentication uses local `loginId` and password credentials in both dev and prod. External OAuth/OIDC provider registration, redirect URIs, and provider-specific keys or secrets are not infrastructure prerequisites. Consumer authentication is outside this Terraform root's ownership boundary.

## Bootstrap Apply

Copy `tfvars/prod.tfvars.example` to an ignored local `tfvars/prod.tfvars`, then keep `enable_distribution = false`.

```shell
terraform init -reconfigure -backend-config=backend/prod.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -var-file=tfvars/prod.tfvars -out=/tmp/admin-web-bootstrap.tfplan
terraform show /tmp/admin-web-bootstrap.tfplan
terraform apply /tmp/admin-web-bootstrap.tfplan
```

The saved plan must contain additions only. Stop if it contains any change or destroy action.

Add each `certificate_validation_records` output to Cloudflare as a DNS-only CNAME. Do not proxy ACM validation records. Wait until the certificate is `ISSUED`.

## CloudFront Apply

Set `enable_distribution = true`, create a new saved plan, and apply only after confirming it contains no product resource address and no destroy action.

After apply, create a DNS-only Cloudflare CNAME:

- Name: `admin`.
- Target: the `cloudfront_domain_name` output.

CloudFront has no global custom error response. Its viewer-request function is attached only to the default S3 behavior, while `/api/admin/*` uses an ordered behavior with caching disabled and all viewer values except `Host` forwarded to `api.cchaksa.com`.

## Deployment Credentials

The `deploy_policy_arn` output is safe to attach to the existing GitHub Actions AWS principal. Terraform intentionally does not attach it to an existing IAM user. The policy permits only S3 object deployment and, after CloudFront is enabled, invalidation of this distribution.

The deployment keeps hashed files under `assets/` so an older cached `index.html` never loses its referenced asset during a rollout. Non-versioned files are synchronized separately and `index.html` is uploaded last with `no-cache` headers.

The current backend repository uses static `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` GitHub secrets. OIDC can replace that authentication later without changing this root's resource ownership.

## Verification

After the SPA is deployed and DNS resolves:

```shell
curl -fsS -o /dev/null -w '%{http_code} %{content_type}\n' https://admin.cchaksa.com/reports/example
curl -sS -o /tmp/admin-api-response -D /tmp/admin-api-headers https://admin.cchaksa.com/api/admin/auth/me
```

The SPA route should return HTML. The API request may return an authentication error, but its body and content type must be the API response rather than `index.html`.
