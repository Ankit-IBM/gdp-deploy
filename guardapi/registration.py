"""Collector/Aggregator registration adapter boundary.

Guardium registration endpoints and parameters are release-specific. This module
intentionally refuses to guess them; a verified release adapter must be supplied.
"""


class RegistrationNotImplemented(RuntimeError):
    """Raised until a supported mechanism is verified for the target release."""


def register_collector(*, collector: str, aggregator: str, version: str) -> None:
    raise RegistrationNotImplemented(
        f"Collector registration for Guardium {version} is not enabled; verify the supported IBM mechanism first"
    )