"""Guardium appliance health-check via REST API.

Checks: login (token), system status, disk usage, S-TAP connections,
        replication status (aggregator), policy install status.
"""
from __future__ import annotations
import logging
import os
from typing import Any

from .client import GuardiumClient, GuardiumApiError

LOG = logging.getLogger(__name__)

_SYSTEM_STATUS_PATH = "/restAPI/system_status"
_DISK_STATUS_PATH   = "/restAPI/disk_status"
_STAP_STATUS_PATH   = "/restAPI/tap_status"
_MANAGED_UNITS_PATH = "/restAPI/managed_units"
_POLICY_STATUS_PATH = "/restAPI/policy"
_PATCH_LEVEL_PATH   = "/restAPI/patch_level"


def check_appliance(
    *,
    appliance_url: str,
    username: str,
    password: str,
    role: str = "collector",
    verify_tls: bool = False,
) -> dict[str, Any]:
    """Run a full health-check on one Guardium appliance. Returns a status dict."""
    client = GuardiumClient(
        base_url=appliance_url, username=username, password=password, verify_tls=verify_tls
    )
    result: dict[str, Any] = {
        "url": appliance_url, "role": role, "healthy": False, "checks": {}
    }

    # 1. Connectivity / auth
    try:
        sys_status = client.request("GET", _SYSTEM_STATUS_PATH) or {}
        result["checks"]["connectivity"] = "OK"
        result["hostname"] = sys_status.get("hostname", appliance_url)
        result["version"]  = sys_status.get("version", "unknown")
    except GuardiumApiError as exc:
        result["checks"]["connectivity"] = f"FAIL: {exc}"
        return result

    # 2. Disk usage
    try:
        disk = client.request("GET", _DISK_STATUS_PATH) or {}
        used_pct = disk.get("usedPercentage", disk.get("used_pct", "?"))
        label = f"OK ({used_pct}% used)"
        if isinstance(used_pct, (int, float)) and used_pct > 85:
            label = f"WARN: disk {used_pct}% used"
        result["checks"]["disk"] = label
    except GuardiumApiError:
        result["checks"]["disk"] = "SKIP (endpoint not available)"

    # 3. S-TAP connections
    try:
        taps = client.request("GET", _STAP_STATUS_PATH) or {}
        tap_list = taps.get("taps", taps if isinstance(taps, list) else [])
        connected = len([t for t in tap_list
                         if str(t.get("status", "")).upper() in ("ACTIVE", "CONNECTED", "UP")])
        total = len(tap_list)
        result["checks"]["stap_connections"] = f"{connected}/{total} connected"
        result["stap_count"] = total
    except GuardiumApiError:
        result["checks"]["stap_connections"] = "SKIP"

    # 4. Managed units (aggregator / central_manager)
    if role in ("aggregator", "central_manager"):
        try:
            units = client.request("GET", _MANAGED_UNITS_PATH) or {}
            collector_list = units.get("managedUnits", [])
            result["checks"]["managed_units"] = (
                f"{len(collector_list)} collector(s) registered"
            )
            result["managed_units"] = [
                u.get("ip") or u.get("hostname") for u in collector_list
            ]
        except GuardiumApiError:
            result["checks"]["managed_units"] = "SKIP"

    # 5. Policies
    try:
        policies = client.request("GET", _POLICY_STATUS_PATH) or {}
        policy_list = policies.get("policies", policies if isinstance(policies, list) else [])
        installed = [
            p.get("policyName", p.get("name", "?"))
            for p in policy_list
            if p.get("installed") or str(p.get("status", "")).upper() == "INSTALLED"
        ]
        names = ", ".join(installed) if installed else "none"
        result["checks"]["policies"] = f"{len(installed)} installed: {names}"
    except GuardiumApiError:
        result["checks"]["policies"] = "SKIP"

    # 6. Patch level
    try:
        patch = client.request("GET", _PATCH_LEVEL_PATH) or {}
        result["checks"]["patch_level"] = patch.get("patchLevel", patch.get("level", "unknown"))
    except GuardiumApiError:
        result["checks"]["patch_level"] = "SKIP"

    result["healthy"] = all(
        not str(v).startswith("FAIL") for v in result["checks"].values()
    )
    return result


def check_all_appliances(config: dict, verify_tls: bool = False) -> list[dict]:
    """Check collector, aggregator (and optionally central_manager) from a config dict."""
    results = []
    for role in ("collector", "aggregator", "central_manager"):
        cfg = config.get(role, {})
        if not cfg.get("enabled", role != "central_manager"):
            continue
        ip = cfg.get("ip", "")
        if not ip:
            continue
        url  = f"https://{ip}:8443"
        user = os.environ.get(f"GUARDIUM_{role.upper()}_USERNAME", "admin")
        pw   = os.environ.get(f"GUARDIUM_{role.upper()}_PASSWORD", "")
        if not pw:
            LOG.warning("No password env var GUARDIUM_%s_PASSWORD — skipping %s", role.upper(), role)
            continue
        LOG.info("Checking %s at %s", role, url)
        results.append(check_appliance(
            appliance_url=url, username=user, password=pw, role=role, verify_tls=verify_tls
        ))
    return results


def print_health_report(results: list[dict]) -> None:
    """Pretty-print health check results to stdout."""
    sep = "-" * 70
    print()
    print("=" * 70)
    print("  IBM Guardium -- Appliance Health Report")
    print("=" * 70)
    for r in results:
        ok = r.get("healthy")
        icon = "[OK]" if ok else "[FAIL]"
        print(f"\n{icon}  {r.get('role','?').upper()}  |  "
              f"{r.get('hostname', r.get('url','?'))}  |  v{r.get('version','?')}")
        print(sep)
        for check, val in r.get("checks", {}).items():
            s = str(val)
            status = "[OK]   " if s.startswith("OK") or s.startswith("SKIP") else \
                     "[WARN] " if s.startswith("WARN") else "[FAIL] "
            print(f"  {status}  {check:<25}  {val}")
    print()
