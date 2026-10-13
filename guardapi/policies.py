"""Sample Guardium security policy deployment via REST API (v12.x).

REST paths used (Guardium 12.x API reference):
  POST /restAPI/policy            -- create policy
  POST /restAPI/policy_rule       -- add rule to policy
  POST /restAPI/install_policy    -- activate policy on the appliance
  GET  /restAPI/policy            -- list policies

Policy sets:
  standard  -- BASELINE_AUDIT, PCI_DSS_AUDIT, HIPAA_AUDIT, EXTRUSION_DETECT
  extended  -- standard + GDPR_PII_AUDIT, SOX_FINANCIAL_AUDIT, CIS_HARDENING_AUDIT
  all       -- all 7 policies
"""

from __future__ import annotations

import argparse
import logging
import os
import sys

from .client import GuardiumClient, GuardiumApiError

LOG = logging.getLogger(__name__)

# ── Standard policies ─────────────────────────────────────────────────────────
STANDARD_POLICIES: list[dict] = [
    {
        "name": "BASELINE_AUDIT",
        "description": "Audit all privileged DB user activity",
        "rules": [
            {
                "description": "Audit DBA activity",
                "db_users": ["sys", "dba", "sa", "root", "postgres", "admin"],
                "actions": ["SELECT", "INSERT", "UPDATE", "DELETE", "EXECUTE", "ALTER", "DROP", "CREATE"],
                "severity": "HIGH",
                "alert": True,
            },
            {
                "description": "Audit schema changes",
                "actions": ["ALTER", "DROP", "CREATE", "TRUNCATE"],
                "severity": "HIGH",
                "alert": True,
            },
        ],
    },
    {
        "name": "PCI_DSS_AUDIT",
        "description": "PCI-DSS cardholder data access audit",
        "rules": [
            {
                "description": "Audit access to cardholder tables",
                "db_objects": ["card%", "payment%", "credit%", "chd%"],
                "actions": ["SELECT", "INSERT", "UPDATE", "DELETE"],
                "severity": "HIGH",
                "alert": True,
            },
            {
                "description": "Log failed logins",
                "actions": ["FAILED_LOGIN"],
                "severity": "CRITICAL",
                "alert": True,
            },
        ],
    },
    {
        "name": "HIPAA_AUDIT",
        "description": "HIPAA PHI access audit",
        "rules": [
            {
                "description": "Audit access to PHI tables",
                "db_objects": ["patient%", "phi%", "medical%", "health%"],
                "actions": ["SELECT", "INSERT", "UPDATE", "DELETE"],
                "severity": "HIGH",
                "alert": True,
            },
        ],
    },
    {
        "name": "EXTRUSION_DETECT",
        "description": "Detect large result-set exfiltration (>1000 rows)",
        "rules": [
            {
                "description": "Alert on mass SELECT",
                "actions": ["SELECT"],
                "min_total_objects": 1000,
                "severity": "CRITICAL",
                "alert": True,
            },
        ],
    },
]

# ── Extended policies: GDPR, SOX, CIS ────────────────────────────────────────
EXTENDED_POLICIES: list[dict] = [
    {
        "name": "GDPR_PII_AUDIT",
        "description": "GDPR — monitor access to Personally Identifiable Information tables",
        "rules": [
            {
                "description": "Audit PII data access",
                "db_objects": [
                    "user%", "person%", "customer%", "employee%",
                    "email%", "phone%", "address%", "ssn%", "pii%",
                ],
                "actions": ["SELECT", "INSERT", "UPDATE", "DELETE"],
                "severity": "HIGH",
                "alert": True,
            },
            {
                "description": "Alert on bulk PII export (>500 rows)",
                "actions": ["SELECT"],
                "min_total_objects": 500,
                "severity": "CRITICAL",
                "alert": True,
            },
        ],
    },
    {
        "name": "SOX_FINANCIAL_AUDIT",
        "description": "Sarbanes-Oxley — audit financial data integrity",
        "rules": [
            {
                "description": "Audit financial table modifications",
                "db_objects": [
                    "account%", "ledger%", "journal%", "transaction%",
                    "invoice%", "payment%", "balance%", "fiscal%",
                ],
                "actions": ["INSERT", "UPDATE", "DELETE", "TRUNCATE", "DROP"],
                "severity": "CRITICAL",
                "alert": True,
            },
            {
                "description": "Audit financial reporting tables",
                "db_objects": ["report%", "audit%", "statement%", "revenue%"],
                "actions": ["SELECT", "INSERT", "UPDATE", "DELETE"],
                "severity": "HIGH",
                "alert": True,
            },
        ],
    },
    {
        "name": "CIS_HARDENING_AUDIT",
        "description": "CIS Benchmark — track privilege escalation and policy violations",
        "rules": [
            {
                "description": "Audit GRANT/REVOKE privilege changes",
                "actions": ["GRANT", "REVOKE"],
                "severity": "CRITICAL",
                "alert": True,
            },
            {
                "description": "Audit DDL on system catalogs",
                "db_objects": [
                    "sys%", "information_schema%", "pg_catalog%", "mysql%",
                ],
                "actions": ["ALTER", "DROP", "CREATE", "TRUNCATE"],
                "severity": "CRITICAL",
                "alert": True,
            },
            {
                "description": "Detect privileged user access",
                "db_users": ["sys", "dba", "sa", "root", "postgres", "admin", "sysdba"],
                "actions": ["SELECT", "INSERT", "UPDATE", "DELETE", "EXECUTE", "ALTER", "DROP", "CREATE"],
                "severity": "HIGH",
                "alert": True,
            },
        ],
    },
]

# ── Merged collections ────────────────────────────────────────────────────────
SAMPLE_POLICIES = STANDARD_POLICIES          # legacy alias
ALL_POLICIES    = STANDARD_POLICIES + EXTENDED_POLICIES

POLICY_SETS: dict[str, list[dict]] = {
    "standard": STANDARD_POLICIES,
    "extended": ALL_POLICIES,
    "all":      ALL_POLICIES,
}


def _policy_payload(p: dict) -> dict:
    return {
        "policyName":        p["name"],
        "policyDescription": p.get("description", ""),
        "policyType":        "SECURITY",
        "ignoreSqlErrors":   False,
    }


def _rule_payload(policy_name: str, rule: dict, idx: int) -> dict:
    payload: dict = {
        "policyName":    policy_name,
        "ruleName":      f"{policy_name}_RULE_{idx + 1:03d}",
        "ruleDescription": rule.get("description", ""),
        "severity":      rule.get("severity", "MEDIUM"),
        "alert":         rule.get("alert", False),
        "logFullDetails": True,
    }
    if "db_users"   in rule: payload["dbUsersPredicate"]   = {"users":   rule["db_users"],   "inclusive": True}
    if "db_objects" in rule: payload["dbObjectsPredicate"] = {"objects": rule["db_objects"], "inclusive": True}
    if "actions"    in rule: payload["commandsPredicate"]  = {"commands": rule["actions"],   "inclusive": True}
    if "min_total_objects" in rule: payload["minTotalObjects"] = rule["min_total_objects"]
    return payload


def deploy_sample_policies(
    *,
    collector_url: str,
    username: str,
    password: str,
    verify_tls: bool = False,
    install: bool = True,
    policies: list[dict] | None = None,
    policy_set: str = "standard",
) -> list[str]:
    """Create and optionally activate policies on a Collector."""
    if policies is None:
        policies = POLICY_SETS.get(policy_set, STANDARD_POLICIES)
    client = GuardiumClient(
        base_url=collector_url, username=username, password=password, verify_tls=verify_tls
    )
    deployed: list[str] = []
    for p in policies:
        name = p["name"]
        LOG.info("Creating policy: %s", name)
        try:
            client.request("POST", "/restAPI/policy", _policy_payload(p))
        except GuardiumApiError as exc:
            if "already exists" in str(exc).lower() or "duplicate" in str(exc).lower():
                LOG.warning("Policy %s already exists; skipping create", name)
            else:
                LOG.error("Failed to create policy %s: %s", name, exc)
                continue
        for i, rule in enumerate(p.get("rules", [])):
            LOG.info("  Adding rule %d to %s", i + 1, name)
            try:
                client.request("POST", "/restAPI/policy_rule", _rule_payload(name, rule, i))
            except GuardiumApiError as exc:
                LOG.error("  Rule %d failed: %s", i + 1, exc)
        if install:
            LOG.info("Activating policy: %s", name)
            try:
                client.request("POST", "/restAPI/install_policy", {"policyName": name})
            except GuardiumApiError as exc:
                LOG.error("Failed to install policy %s: %s", name, exc)
                continue
        deployed.append(name)
    LOG.info("Deployed %d policies: %s", len(deployed), deployed)
    return deployed


def list_policies(
    *, collector_url: str, username: str, password: str, verify_tls: bool = False
) -> list[dict]:
    client = GuardiumClient(
        base_url=collector_url, username=username, password=password, verify_tls=verify_tls
    )
    result = client.request("GET", "/restAPI/policy") or {}
    return result.get("policies", result if isinstance(result, list) else [])


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Deploy sample Guardium policies")
    parser.add_argument("--url",          default=os.environ.get("GUARDIUM_URL"),      required=True)
    parser.add_argument("--username",     default=os.environ.get("GUARDIUM_USERNAME"), required=True)
    parser.add_argument("--password",     default=os.environ.get("GUARDIUM_PASSWORD"), required=True)
    parser.add_argument("--policy-set",   default="standard",
                        choices=["standard", "extended", "all"],
                        help="Which policy set to deploy (default: standard)")
    parser.add_argument("--no-install",    action="store_true")
    parser.add_argument("--no-verify-tls", action="store_true")
    parser.add_argument("--list",          action="store_true",
                        help="List existing policies and exit")
    args = parser.parse_args()
    if args.list:
        for p in list_policies(
            collector_url=args.url, username=args.username, password=args.password,
            verify_tls=not args.no_verify_tls,
        ):
            print(p)
        return
    deployed = deploy_sample_policies(
        collector_url=args.url,
        username=args.username,
        password=args.password,
        verify_tls=not args.no_verify_tls,
        install=not args.no_install,
        policy_set=args.policy_set,
    )
    print(f"Deployed {len(deployed)} policies: {', '.join(deployed)}")


if __name__ == "__main__":
    main()
