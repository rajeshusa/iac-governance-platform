# AI-Assisted IaC Governance Platform

An end-to-end Infrastructure-as-Code governance platform built with Terraform, GitHub Actions, and AI-powered risk analysis.

## Architecture

```
Developer opens PR
       │
       ▼
GitHub Actions triggers
       │
       ├──► terraform validate + plan (saves plan.json)
       │
       ├──► Checkov security scan     ──► PR Comment
       │
       ├──► OPA policy enforcement    ──► PR Comment
       │
       ├──► Infracost cost analysis   ──► PR Comment
       │
       └──► AI Risk Summarizer        ──► PR Comment (consolidated)
                                              │
                                              ▼
                                    Reviewers approve by risk tier
                                              │
                                              ▼
                                    Merge → terraform apply (prod-gated)
```

## Repo Structure

```
.
├── .github/workflows/
│   ├── tf-plan.yml          # PR: validate, plan, scan, summarize
│   └── tf-apply.yml         # Main: gated apply per environment
├── terraform/
│   ├── modules/             # Reusable Terraform modules
│   │   ├── vpc/
│   │   ├── ec2/
│   │   ├── s3/
│   │   └── rds/
│   └── environments/        # Per-environment root configs
│       ├── dev/
│       ├── staging/
│       └── prod/
├── policies/
│   └── opa/                 # OPA Rego policy files
├── security/
│   └── .checkov.yml         # Checkov config
├── cost/
│   └── infracost.yml        # Infracost config
├── ai-summarizer/
│   └── summarize.py         # AI risk summary generator
└── scripts/
    └── post_comment.sh      # GitHub PR comment helper
```

## Key Features

| Feature | Tool | Stage |
|---|---|---|
| IaC Validation | terraform validate + tflint | PR |
| Security Scanning | Checkov | PR |
| Policy Enforcement | OPA / Rego | PR |
| Cost Analysis | Infracost | PR |
| AI Risk Summary | Claude API | PR |
| Gated Deployment | GitHub Environments | Merge |
| Drift Detection | Scheduled workflow | Nightly |

## Setup

1. Configure AWS OIDC role (see `scripts/setup-oidc.sh`)
2. Add GitHub Secrets: `ANTHROPIC_API_KEY`, `INFRACOST_API_KEY`
3. Set branch protection rules requiring all status checks
4. Configure `CODEOWNERS` for your team structure
