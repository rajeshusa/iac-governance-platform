#!/usr/bin/env python3
"""
AI-Assisted IaC Governance Platform
AI Risk Summarizer

Collects outputs from Checkov, OPA, and Infracost, feeds them to Claude,
and posts a consolidated risk summary as a GitHub PR comment.
"""

import argparse
import json
import os
import sys
import requests
import anthropic
from dataclasses import dataclass
from typing import Optional


# ─────────────────────────────────────────────
# Data Classes
# ─────────────────────────────────────────────

@dataclass
class PlanSummary:
    adds: int
    changes: int
    destroys: int
    resources_changed: list[dict]

@dataclass
class SecurityFinding:
    check_id: str
    name: str
    resource: str
    severity: str
    file: str

@dataclass
class PolicyViolation:
    message: str

@dataclass
class CostSummary:
    monthly_cost_before: float
    monthly_cost_after: float
    monthly_diff: float
    currency: str = "USD"

@dataclass
class GovernanceReport:
    environment: str
    plan: PlanSummary
    security_findings: list[SecurityFinding]
    policy_violations: list[PolicyViolation]
    cost: Optional[CostSummary]


# ─────────────────────────────────────────────
# Parsers
# ─────────────────────────────────────────────

def parse_plan(plan_path: str) -> PlanSummary:
    """Parse terraform show -json output into structured summary."""
    with open(plan_path) as f:
        plan = json.load(f)

    resource_changes = plan.get("resource_changes", [])
    adds, changes, destroys = 0, 0, 0
    changed_resources = []

    for rc in resource_changes:
        actions = rc.get("change", {}).get("actions", [])
        resource_info = {
            "address": rc.get("address"),
            "type": rc.get("type"),
            "actions": actions
        }

        if "create" in actions:
            adds += 1
            changed_resources.append(resource_info)
        elif "update" in actions:
            changes += 1
            changed_resources.append(resource_info)
        elif "delete" in actions:
            destroys += 1
            changed_resources.append(resource_info)

    return PlanSummary(
        adds=adds,
        changes=changes,
        destroys=destroys,
        resources_changed=changed_resources[:20]  # Cap for token budget
    )


def parse_checkov(checkov_path: str) -> list[SecurityFinding]:
    """Parse Checkov JSON results into security findings."""
    findings = []

    try:
        with open(checkov_path) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return findings

    # Checkov can return a list (multi-framework) or single object
    checks_list = data if isinstance(data, list) else [data]

    for check_group in checks_list:
        failed = check_group.get("results", {}).get("failed_checks", [])
        for check in failed:
            findings.append(SecurityFinding(
                check_id=check.get("check_id", "UNKNOWN"),
                name=check.get("check", {}).get("name", "Unknown check") if isinstance(check.get("check"), dict) else str(check.get("check", "")),
                resource=check.get("resource", ""),
                severity=check.get("severity", "MEDIUM"),
                file=check.get("repo_file_path", "")
            ))

    return findings


def parse_opa(opa_path: str) -> list[PolicyViolation]:
    """Parse OPA evaluation results into policy violations."""
    violations = []

    try:
        with open(opa_path) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return violations

    items = data.get("result", [{}])[0].get("expressions", [{}])[0].get("value", [])
    for item in items:
        violations.append(PolicyViolation(message=str(item)))

    return violations


def parse_infracost(infracost_path: str) -> Optional[CostSummary]:
    """Parse Infracost diff output into cost summary."""
    try:
        with open(infracost_path) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return None

    summary = data.get("summary", {})
    before = float(data.get("pastTotalMonthlyCost", 0) or 0)
    after = float(data.get("totalMonthlyCost", 0) or 0)

    return CostSummary(
        monthly_cost_before=before,
        monthly_cost_after=after,
        monthly_diff=after - before
    )


# ─────────────────────────────────────────────
# AI Risk Analysis
# ─────────────────────────────────────────────

SYSTEM_PROMPT = """You are an expert infrastructure security and reliability engineer 
reviewing Infrastructure-as-Code changes before deployment to production.

Your job is to analyze Terraform plan changes, security scan findings, policy violations, 
and cost impacts — then produce a clear, actionable risk summary for the engineering team.

Always respond with valid JSON matching this exact schema:
{
  "risk_level": "HIGH" | "MEDIUM" | "LOW" | "NONE",
  "risk_score": <integer 0-100>,
  "headline": "<one sentence summary of what this PR does>",
  "risk_summary": "<2-3 sentences explaining the main risks>",
  "top_findings": [
    {
      "severity": "HIGH" | "MEDIUM" | "LOW",
      "category": "Security" | "Policy" | "Cost" | "Reliability" | "Blast Radius",
      "finding": "<concise finding description>",
      "recommendation": "<specific action to take>"
    }
  ],
  "blast_radius": "<description of what could break if this goes wrong>",
  "deployment_recommendation": "APPROVE" | "APPROVE_WITH_CAUTION" | "REQUIRES_REVIEW" | "BLOCK",
  "required_approvers": ["<role>"],
  "positive_observations": ["<things done well>"]
}

Risk level rules:
- HIGH: any resource destruction in prod, security group 0.0.0.0/0, unencrypted data store, cost > $500/mo increase, OPA violations
- MEDIUM: new IAM roles/policies, RDS changes, multi-AZ changes, cost $100-500/mo increase
- LOW: tagging changes, autoscaling adjustments, minor config changes, cost < $100/mo
- NONE: documentation/variable changes only, no resource changes
"""

def build_analysis_prompt(report: GovernanceReport) -> str:
    """Build the prompt payload for Claude."""

    resource_list = "\n".join([
        f"  - [{'+' if 'create' in r['actions'] else '~' if 'update' in r['actions'] else '-'}] {r['address']} ({r['type']})"
        for r in report.plan.resources_changed
    ])

    security_list = "\n".join([
        f"  - [{f.severity}] {f.check_id}: {f.name} on {f.resource}"
        for f in report.security_findings[:15]  # Cap for token budget
    ]) or "  None"

    policy_list = "\n".join([
        f"  - {v.message}"
        for v in report.policy_violations
    ]) or "  None"

    cost_section = "  Not available"
    if report.cost:
        sign = "+" if report.cost.monthly_diff >= 0 else ""
        before = report.cost.monthly_cost_before
        after = report.cost.monthly_cost_after
        diff = report.cost.monthly_diff
        cost_section = (
            "  Before: ${:.2f}/mo\n  After:  ${:.2f}/mo\n  Delta:  {}${:.2f}/mo".format(
                before, after, sign, diff
            )
        )

    return f"""Analyze this Terraform PR for environment: **{report.environment.upper()}**

## Plan Summary
- Resources to ADD: {report.plan.adds}
- Resources to CHANGE: {report.plan.changes}  
- Resources to DESTROY: {report.plan.destroys}

## Resources Being Changed
{resource_list or '  No resource changes'}

## Security Scan Findings ({len(report.security_findings)} total)
{security_list}

## Policy Violations ({len(report.policy_violations)} total)
{policy_list}

## Cost Impact
{cost_section}

Provide your risk assessment as JSON per the schema. Be specific and actionable.
Focus especially on: data exposure risks, IAM privilege escalation, destructive changes, and unexpected cost spikes."""


def analyze_with_ai(report: GovernanceReport) -> dict:
    """Send report to Claude API and get structured risk assessment."""
    client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])

    prompt = build_analysis_prompt(report)

    message = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=1500,
        system=SYSTEM_PROMPT,
        messages=[
            {"role": "user", "content": prompt}
        ]
    )

    response_text = message.content[0].text

    # Parse JSON response
    try:
        return json.loads(response_text)
    except json.JSONDecodeError:
        # Extract JSON if wrapped in markdown
        import re
        match = re.search(r'\{.*\}', response_text, re.DOTALL)
        if match:
            return json.loads(match.group())
        raise ValueError(f"Could not parse AI response as JSON: {response_text[:200]}")


# ─────────────────────────────────────────────
# GitHub PR Comment
# ─────────────────────────────────────────────

RISK_COLORS = {
    "HIGH":   "🔴",
    "MEDIUM": "🟡",
    "LOW":    "🟢",
    "NONE":   "⚪"
}

DEPLOY_LABELS = {
    "APPROVE":              "✅ Approve",
    "APPROVE_WITH_CAUTION": "⚠️ Approve with Caution",
    "REQUIRES_REVIEW":      "🔍 Requires Review",
    "BLOCK":                "🚫 Block — Do Not Merge"
}

def format_pr_comment(report: GovernanceReport, analysis: dict, environment: str) -> str:
    """Format the AI analysis as a rich GitHub PR comment."""

    risk_level = analysis.get("risk_level", "UNKNOWN")
    risk_emoji = RISK_COLORS.get(risk_level, "❓")
    deploy_rec = analysis.get("deployment_recommendation", "REQUIRES_REVIEW")
    deploy_label = DEPLOY_LABELS.get(deploy_rec, deploy_rec)

    # Top findings table
    findings_rows = ""
    for f in analysis.get("top_findings", []):
        sev_emoji = {"HIGH": "🔴", "MEDIUM": "🟡", "LOW": "🟢"}.get(f.get("severity", ""), "⚪")
        findings_rows += (
            f"| {sev_emoji} {f.get('severity')} | {f.get('category')} | "
            "{} | {} |\n".format(f.get('finding'), f.get('recommendation'))
        )

    # Required approvers
    approvers = ", ".join([f"`{a}`" for a in analysis.get("required_approvers", ["Engineering Lead"])]) or "`Engineering Lead`"

    # Positive observations
    positives = "\n".join([f"- ✅ {p}" for p in analysis.get("positive_observations", [])]) or "_None noted_"

    comment = f"""## {risk_emoji} AI Risk Summary — `{environment}` 

> **{analysis.get('headline', 'Infrastructure change detected')}**

### Risk Assessment
| Field | Value |
|---|---|
| **Risk Level** | {risk_emoji} **{risk_level}** (Score: {analysis.get('risk_score', 'N/A')}/100) |
| **Deployment Recommendation** | {deploy_label} |
| **Required Approvers** | {approvers} |
| **Blast Radius** | {analysis.get('blast_radius', 'Unknown')} |

### Summary
{analysis.get('risk_summary', 'No summary available.')}

### Top Findings
| Severity | Category | Finding | Recommendation |
|---|---|---|---|
{findings_rows or '| ⚪ NONE | — | No significant findings | — |\n'}

### Change Statistics
| | Count |
|---|---|
| ➕ Resources Added | `{report.plan.adds}` |
| 🔄 Resources Changed | `{report.plan.changes}` |
| ❌ Resources Destroyed | `{report.plan.destroys}` |
| 🛡️ Security Findings | `{len(report.security_findings)}` |
| 📋 Policy Violations | `{len(report.policy_violations)}` |

### What's Done Well
{positives}

---
<sub>🤖 Generated by AI Risk Summarizer · Powered by Claude</sub>
"""
    return comment


def post_github_comment(comment: str, pr_number: str, repo: str, token: str):
    """Post comment to GitHub PR via REST API."""
    url = f"https://api.github.com/repos/{repo}/issues/{pr_number}/comments"
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28"
    }
    response = requests.post(url, headers=headers, json={"body": comment})
    response.raise_for_status()
    print(f"✅ Posted AI risk summary to PR #{pr_number}")


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="AI-powered IaC risk summarizer")
    parser.add_argument("--plan-json",      required=True, help="Path to terraform show -json output")
    parser.add_argument("--checkov-json",   required=True, help="Path to Checkov JSON results")
    parser.add_argument("--opa-json",       required=True, help="Path to OPA evaluation results")
    parser.add_argument("--infracost-json", required=True, help="Path to Infracost diff JSON")
    args = parser.parse_args()

    environment = os.environ.get("ENVIRONMENT", "unknown")
    pr_number   = os.environ.get("PR_NUMBER")
    repo        = os.environ.get("REPO")
    token       = os.environ.get("GITHUB_TOKEN")

    print(f"🔍 Analyzing infrastructure changes for environment: {environment}")

    # Parse all tool outputs
    print("  Parsing Terraform plan...")
    plan = parse_plan(args.plan_json)

    print("  Parsing Checkov security findings...")
    security_findings = parse_checkov(args.checkov_json)

    print("  Parsing OPA policy violations...")
    policy_violations = parse_opa(args.opa_json)

    print("  Parsing Infracost cost analysis...")
    cost = parse_infracost(args.infracost_json)

    report = GovernanceReport(
        environment=environment,
        plan=plan,
        security_findings=security_findings,
        policy_violations=policy_violations,
        cost=cost
    )

    print(f"  Plan: +{plan.adds} ~{plan.changes} -{plan.destroys} resources")
    print(f"  Security findings: {len(security_findings)}")
    print(f"  Policy violations: {len(policy_violations)}")

    # AI analysis
    print("🤖 Sending to Claude for risk analysis...")
    try:
        analysis = analyze_with_ai(report)
        print(f"  Risk level: {analysis.get('risk_level')} ({analysis.get('risk_score')}/100)")
        print(f"  Recommendation: {analysis.get('deployment_recommendation')}")
    except Exception as e:
        print(f"⚠️  AI analysis failed: {e}")
        # Fallback summary if AI is unavailable
        analysis = {
            "risk_level": "UNKNOWN",
            "risk_score": 50,
            "headline": "AI analysis unavailable — manual review required",
            "risk_summary": f"The AI summarizer encountered an error: {str(e)[:100]}. Please review the individual scan results above.",
            "top_findings": [],
            "blast_radius": "Unknown — see individual scan results",
            "deployment_recommendation": "REQUIRES_REVIEW",
            "required_approvers": ["Engineering Lead"],
            "positive_observations": []
        }

    # Format and post comment
    comment = format_pr_comment(report, analysis, environment)

    if pr_number and repo and token:
        post_github_comment(comment, pr_number, repo, token)
    else:
        print("\n--- PR COMMENT PREVIEW ---")
        print(comment)
        print("--- END PREVIEW ---")


if __name__ == "__main__":
    main()
