# GitHub Setup Guide

Step-by-step instructions to create the GitHub repo and push this project.

---

## Step 1 — Install Prerequisites (once)

```bash
# Git
git --version   # should be 2.x+

# GitHub CLI (makes repo creation easy)
# macOS
brew install gh

# Linux
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
  https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh
```

---

## Step 2 — Authenticate GitHub CLI

```bash
gh auth login
# Choose: GitHub.com → HTTPS → Login with browser
```

---

## Step 3 — Create the Repository

```bash
gh repo create iac-governance-platform \
  --private \
  --description "AI-Assisted IaC Governance Platform using Terraform, GitHub Actions, and Claude" \
  --clone=false
```

---

## Step 4 — Push the Code

```bash
# Navigate to the project folder (wherever you unzipped it)
cd iac-governance-platform

# Initialize git and push
git init
git add .
git commit -m "feat: initial IaC governance platform setup"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/iac-governance-platform.git
git push -u origin main
```

> Replace `YOUR_USERNAME` with your GitHub username or org name.

---

## Step 5 — Add GitHub Secrets

Go to: **Settings → Secrets and variables → Actions → New repository secret**

| Secret Name | Value | Where to get it |
|---|---|---|
| `ANTHROPIC_API_KEY` | `sk-ant-...` | console.anthropic.com → API Keys |
| `INFRACOST_API_KEY` | `ico-...` | infracost.io → Org Settings |
| `AWS_ROLE_DEV` | `arn:aws:iam::123456789012:role/github-actions-...-dev` | Run `scripts/setup-oidc.sh` |
| `AWS_ROLE_STAGING` | `arn:aws:iam::123456789012:role/github-actions-...-staging` | Run `scripts/setup-oidc.sh` |
| `AWS_ROLE_PROD` | `arn:aws:iam::123456789012:role/github-actions-...-prod` | Run `scripts/setup-oidc.sh` |
| `TF_VAR_db_password` | your-db-password | Set a strong password |

```bash
# Or use GitHub CLI:
gh secret set ANTHROPIC_API_KEY --body "sk-ant-YOUR_KEY"
gh secret set INFRACOST_API_KEY --body "ico-YOUR_KEY"
gh secret set AWS_ROLE_DEV      --body "arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME"
```

---

## Step 6 — Configure AWS OIDC (one-time per environment)

```bash
chmod +x scripts/setup-oidc.sh

# Run for each environment
./scripts/setup-oidc.sh YOUR_GITHUB_ORG iac-governance-platform dev     YOUR_AWS_ACCOUNT_ID
./scripts/setup-oidc.sh YOUR_GITHUB_ORG iac-governance-platform staging  YOUR_AWS_ACCOUNT_ID
./scripts/setup-oidc.sh YOUR_GITHUB_ORG iac-governance-platform prod     YOUR_AWS_ACCOUNT_ID
```

---

## Step 7 — Set Branch Protection Rules

Go to: **Settings → Branches → Add branch protection rule**

- Branch name pattern: `main`
- ✅ Require a pull request before merging
- ✅ Require status checks to pass:
  - `Plan (dev)`
  - `Security Scan (Checkov)`
  - `OPA Policy Check (dev)`
  - `Cost Analysis (Infracost)`
  - `AI Risk Summary (dev)`
- ✅ Require branches to be up to date
- ✅ Require linear history
- ✅ Do not allow bypassing the above settings

---

## Step 8 — Set Up GitHub Environments

Go to: **Settings → Environments**

Create three environments with these protection rules:

| Environment | Required Reviewers | Wait Timer |
|---|---|---|
| `dev` | None | None |
| `staging` | 1 (your SRE team) | None |
| `prod` | 2 (SRE + Security) | 30 minutes |

---

## Step 9 — Test the Pipeline

```bash
# Create a feature branch and make a small Terraform change
git checkout -b test/add-s3-bucket

# Edit terraform/environments/dev/main.tf to add a resource
# Then open a PR:
gh pr create \
  --title "test: verify governance pipeline" \
  --body "Testing the full CI governance pipeline"
```

You should see all 6 workflow jobs trigger and post comments on the PR.

---

## Step 10 — Update Your tfvars

Before running `terraform apply` for real:

1. `terraform/environments/*/terraform.tfvars` — update `app_ami_id` with a real AMI
2. `terraform/environments/prod/terraform.tfvars` — update KMS key ARNs
3. Update the S3 backend bucket name in each `main.tf` backend block

---

## Repo Structure (final)

```
iac-governance-platform/
├── .github/
│   └── workflows/
│       ├── tf-plan.yml          # PR pipeline
│       └── tf-apply.yml         # Merge pipeline + drift detection
├── terraform/
│   ├── modules/
│   │   ├── vpc/                 # VPC + flow logs + NAT
│   │   ├── ec2/                 # ASG + IMDSv2 + SSM
│   │   ├── s3/                  # Encrypted + private + versioned
│   │   └── rds/                 # Encrypted + multi-AZ + monitoring
│   └── environments/
│       ├── dev/                 # No NAT, single-AZ, low cost
│       ├── staging/             # NAT, single-AZ RDS, near-prod
│       └── prod/                # Multi-AZ, CMK encryption, HA
├── policies/
│   └── opa/
│       ├── main.rego            # 7 governance policies
│       └── main_test.rego       # OPA unit tests
├── ai-summarizer/
│   ├── summarize.py             # Claude-powered risk summarizer
│   └── requirements.txt
├── security/
│   └── .checkov.yml             # Checkov scan config
├── cost/
│   └── infracost.yml            # Infracost project config
├── scripts/
│   ├── setup-oidc.sh            # One-time AWS OIDC setup
│   └── post_comment.sh          # GitHub PR comment helper
├── .gitignore
├── CODEOWNERS
└── README.md
```
