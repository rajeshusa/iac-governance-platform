#!/bin/bash
# scripts/post_comment.sh
# Helper script to post or update a labelled comment on a GitHub PR
#
# Usage:
#   ./scripts/post_comment.sh \
#     --repo "org/repo" \
#     --pr 42 \
#     --label "<!-- terraform-plan-dev -->" \
#     --body "$(cat comment.md)"
#
# Behavior:
#   - If a comment with the label already exists on the PR → UPDATE it
#   - If no matching comment exists → CREATE a new one
#   This prevents comment spam on repeated workflow runs.

set -euo pipefail

# ─────────────────────────────────────────────
# Argument parsing
# ─────────────────────────────────────────────
REPO=""
PR_NUMBER=""
LABEL=""
BODY=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo)    REPO="$2";      shift 2 ;;
    --pr)      PR_NUMBER="$2"; shift 2 ;;
    --label)   LABEL="$2";     shift 2 ;;
    --body)    BODY="$2";      shift 2 ;;
    *)         echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ─────────────────────────────────────────────
# Validation
# ─────────────────────────────────────────────
if [[ -z "$REPO" || -z "$PR_NUMBER" || -z "$LABEL" || -z "$BODY" ]]; then
  echo "Error: --repo, --pr, --label, and --body are all required"
  exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Error: GITHUB_TOKEN environment variable is not set"
  exit 1
fi

GITHUB_API="https://api.github.com"
AUTH_HEADER="Authorization: Bearer ${GITHUB_TOKEN}"
ACCEPT_HEADER="Accept: application/vnd.github+json"
API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"

# ─────────────────────────────────────────────
# Find existing comment with matching label
# ─────────────────────────────────────────────
echo "Searching for existing comment with label: ${LABEL}"

EXISTING_COMMENT_ID=""
PAGE=1

while true; do
  RESPONSE=$(curl -s \
    -H "${AUTH_HEADER}" \
    -H "${ACCEPT_HEADER}" \
    -H "${API_VERSION_HEADER}" \
    "${GITHUB_API}/repos/${REPO}/issues/${PR_NUMBER}/comments?per_page=100&page=${PAGE}")

  # Check if response is valid JSON array
  if ! echo "$RESPONSE" | jq -e 'type == "array"' > /dev/null 2>&1; then
    echo "Warning: Unexpected API response on page ${PAGE}"
    break
  fi

  COUNT=$(echo "$RESPONSE" | jq 'length')
  if [[ "$COUNT" -eq 0 ]]; then
    break
  fi

  # Search for our labelled comment
  FOUND=$(echo "$RESPONSE" | jq -r --arg label "$LABEL" \
    '.[] | select(.body | contains($label)) | .id' | head -1)

  if [[ -n "$FOUND" ]]; then
    EXISTING_COMMENT_ID="$FOUND"
    break
  fi

  PAGE=$((PAGE + 1))
done

# ─────────────────────────────────────────────
# Prepend label to body so we can find it next time
# ─────────────────────────────────────────────
FULL_BODY="${LABEL}
${BODY}"

# Encode body as JSON
PAYLOAD=$(jq -n --arg body "$FULL_BODY" '{"body": $body}')

# ─────────────────────────────────────────────
# Update existing comment OR create new one
# ─────────────────────────────────────────────
if [[ -n "$EXISTING_COMMENT_ID" ]]; then
  echo "Updating existing comment ID: ${EXISTING_COMMENT_ID}"
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PATCH \
    -H "${AUTH_HEADER}" \
    -H "${ACCEPT_HEADER}" \
    -H "${API_VERSION_HEADER}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "${GITHUB_API}/repos/${REPO}/issues/comments/${EXISTING_COMMENT_ID}")
else
  echo "Creating new comment on PR #${PR_NUMBER}"
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "${AUTH_HEADER}" \
    -H "${ACCEPT_HEADER}" \
    -H "${API_VERSION_HEADER}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "${GITHUB_API}/repos/${REPO}/issues/${PR_NUMBER}/comments")
fi

# ─────────────────────────────────────────────
# Result
# ─────────────────────────────────────────────
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
  echo "✅ Comment posted successfully (HTTP ${HTTP_CODE})"
else
  echo "❌ Failed to post comment (HTTP ${HTTP_CODE})"
  exit 1
fi
