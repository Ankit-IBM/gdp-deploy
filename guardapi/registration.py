"""Collector → Aggregator registration via the Guardium REST API (v12.x).

REST path:  POST /restAPI/register_aggregator   (initiated from the Collector)
CLI equiv:  store aggregator <aggregator_ip>     (run in the Guardium CLI shell)
"""

from __future__ import annotations

import logging
import time

from .client import GuardiumClient, GuardiumApiError

LOG = logging.getLogger(__name__)

_REGISTER_AGG_PATH   = "/restAPI/register_aggregator"
_REGISTER_STATUS_PATH = "/restAPI/aggregator_registration_status"
_MANAGED_UNITS_PATH  = "/restAPI/managed_units"


def register_collector_to_aggregator(
    *,
    collector_url: str,
    collector_username: str,
    collector_password: str,
    aggregator_ip: str,
    aggregator_username: str,
    aggregator_password: str,
    verify_tls: bool = False,
    poll_interval: int = 15,
    poll_timeout: int = 300,
) -> dict:
    """Register a Collector with an Aggregator via the Collector REST API."""
    client = GuardiumClient(
        base_url=collector_url,
        username=collector_username,
        password=collector_password,
        verify_tls=verify_tls,
    )
    payload = {
        "aggregatorIP": aggregator_ip,
        "aggregatorUsername": aggregator_username,
        "aggregatorPassword": aggregator_password,
    }
    LOG.info("Initiating collector→aggregator registration: %s → %s", collector_url, aggregator_ip)
    response = client.request("POST", _REGISTER_AGG_PATH, payload)
    LOG.info("Registration request accepted: %s", response)

    deadline = time.monotonic() + poll_timeout
    status: dict = {}
    while time.monotonic() < deadline:
        time.sleep(poll_interval)
        status = client.request("GET", _REGISTER_STATUS_PATH) or {}
        reg_status = status.get("status", "").lower()
        LOG.info("Registration status: %s", reg_status)
        if reg_status == "registered":
            LOG.info("Collector successfully registered to aggregator %s", aggregator_ip)
            return status
        if reg_status in ("failed", "error"):
            raise GuardiumApiError(f"Registration failed: {status}")

    raise GuardiumApiError(
        f"Registration did not complete within {poll_timeout}s; last status: {status}"
    )


def verify_registration(
    *,
    aggregator_url: str,
    aggregator_username: str,
    aggregator_password: str,
    collector_ip: str,
    verify_tls: bool = False,
) -> bool:
    """Confirm the Aggregator lists the Collector as a managed unit."""
    client = GuardiumClient(
        base_url=aggregator_url,
        username=aggregator_username,
        password=aggregator_password,
        verify_tls=verify_tls,
    )
    units = client.request("GET", _MANAGED_UNITS_PATH) or {}
    for unit in units.get("managedUnits", []):
        if unit.get("ip") == collector_ip or unit.get("hostname") == collector_ip:
            LOG.info("Aggregator confirms collector %s is registered", collector_ip)
            return True
    LOG.warning("Collector %s not found in aggregator managed-units list", collector_ip)
    return False
