#!/bin/bash
# scripts/setup-oidc.sh
# One-time setup: configure AWS OIDC trust for GitHub Actions
# This eliminates the need for long-lived AWS access keys in GitHub Secrets
#
# Usage: ./scripts/setup-oidc.sh <github-org> <github-repo> <environment> <aws-account-id>

set -euo pipefail

GITHUB_ORG="${1:?Usage: $0 <github-org> <github-repo> <environment> <aws-account-id>}"
GITHUB_REPO="${2:?}"
ENVIRONMENT="${3:?}"
AWS_ACCOUNT_ID="${4:?}"
ROLE_NAME="github-actions-${GITHUB_REPO}-${ENVIRONMENT}"
OIDC_PROVIDER="token.actions.githubusercontent.com"

echo "Setting up OIDC role: ${ROLE_NAME}"
echo "  GitHub: ${GITHUB_ORG}/${GITHUB_REPO}"
echo "  Environment: ${ENVIRONMENT}"
echo "  AWS Account: ${AWS_ACCOUNT_ID}"
echo ""

# Create OIDC provider if it doesn't exist
if ! aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}" \
    2>/dev/null; then

    echo "Creating OIDC provider..."
    aws iam create-open-id-connect-provider \
        --url "https://${OIDC_PROVIDER}" \
        --client-id-list "sts.amazonaws.com" \
        --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"
fi

# Build the trust policy
# Scoped to specific repo + environment for least-privilege
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "${OIDC_PROVIDER}:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:${ENVIRONMENT}"
        }
      }
    }
  ]
}
EOF
)

# Create or update the IAM role
if aws iam get-role --role-name "${ROLE_NAME}" 2>/dev/null; then
    echo "Updating existing role: ${ROLE_NAME}"
    aws iam update-assume-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-document "${TRUST_POLICY}"
else
    echo "Creating new role: ${ROLE_NAME}"
    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document "${TRUST_POLICY}" \
        --description "GitHub Actions OIDC role for ${GITHUB_ORG}/${GITHUB_REPO} ${ENVIRONMENT}"
fi

# Attach policies based on environment
if [ "${ENVIRONMENT}" == "prod" ]; then
    # Prod: read-only plan + specific apply permissions only
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/ReadOnlyAccess"
    echo "  Attached ReadOnlyAccess (prod — apply via separate pipeline)"
else
    # Dev/Staging: broader permissions for Terraform to manage resources
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/PowerUserAccess"
    echo "  Attached PowerUserAccess (${ENVIRONMENT})"
fi

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
echo ""
echo "✅ OIDC role ready: ${ROLE_ARN}"
echo ""
echo "Add this to GitHub Secrets:"
echo "  Name:  AWS_ROLE_$(echo ${ENVIRONMENT} | tr '[:lower:]' '[:upper:]')"
echo "  Value: ${ROLE_ARN}"
