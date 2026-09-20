"""Validation adapter boundary for release-specific Guardium checks."""


class ValidationNotImplemented(RuntimeError):
    """Raised when a requested check has not been verified for the release."""


def validate_appliance(*, host: str, role: str, version: str) -> None:
    raise ValidationNotImplemented(
        f"Guardium {version} {role} validation is not enabled until its documented API/CLI is verified"
    )