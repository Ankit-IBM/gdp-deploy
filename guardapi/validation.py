"""Guardium appliance validation helpers."""

import logging
from .client import GuardiumClient

LOG = logging.getLogger(__name__)


def validate_appliance(*, host: str, role: str, version: str,
                       username: str = "admin", password: str = "",
                       verify_tls: bool = False) -> dict:
    """Check basic REST API reachability for a Guardium appliance.

    Calls GET /restAPI/system_info on the appliance and returns the
    response payload. Raises GuardiumApiError on connection failure.
    """
    client = GuardiumClient(
        base_url=f"https://{host}:8443",
        username=username,
        password=password,
        verify_tls=verify_tls,
    )
    LOG.info("Validating Guardium %s appliance at %s (version %s)", role, host, version)
    result = client.request("GET", "/restAPI/system_info") or {}
    LOG.info("Validation response: %s", result)
    return result
