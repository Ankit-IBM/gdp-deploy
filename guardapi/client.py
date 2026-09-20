"""Small, version-neutral HTTPS client for verified Guardium API adapters."""

from __future__ import annotations

import json
import logging
import os
import ssl
import time
from dataclasses import dataclass
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import HTTPSHandler, Request, build_opener

LOG = logging.getLogger(__name__)


class GuardiumApiError(RuntimeError):
    """Raised when a Guardium request cannot be completed safely."""


@dataclass
class GuardiumClient:
    base_url: str
    username: str
    password: str
    verify_tls: bool = True
    timeout: float = 30.0
    retries: int = 2

    @classmethod
    def from_environment(cls) -> "GuardiumClient":
        missing = [name for name in ("GUARDIUM_URL", "GUARDIUM_USERNAME", "GUARDIUM_PASSWORD") if not os.environ.get(name)]
        if missing:
            raise GuardiumApiError(f"Missing required environment variables: {', '.join(missing)}")
        return cls(
            base_url=os.environ["GUARDIUM_URL"].rstrip("/"),
            username=os.environ["GUARDIUM_USERNAME"],
            password=os.environ["GUARDIUM_PASSWORD"],
            verify_tls=os.environ.get("GUARDIUM_VERIFY_TLS", "true").lower() != "false",
        )

    def request(self, method: str, path: str, payload: dict[str, Any] | None = None) -> Any:
        if not path.startswith("/"):
            raise GuardiumApiError("API paths must begin with '/'; endpoint discovery is adapter-specific")
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request = Request(
            f"{self.base_url}{path}",
            data=body,
            method=method.upper(),
            headers={
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
        )
        password_manager = __import__("urllib.request", fromlist=["HTTPPasswordMgrWithDefaultRealm"])
        auth = password_manager.HTTPPasswordMgrWithDefaultRealm()
        auth.add_password(None, self.base_url, self.username, self.password)
        handler = password_manager.HTTPBasicAuthHandler(auth)
        context = ssl.create_default_context() if self.verify_tls else ssl._create_unverified_context()
        opener = build_opener(handler, HTTPSHandler(context=context))
        for attempt in range(self.retries + 1):
            try:
                with opener.open(request, timeout=self.timeout) as response:
                    raw = response.read()
                if not raw:
                    return None
                return json.loads(raw)
            except HTTPError as exc:
                detail = exc.read(512).decode("utf-8", errors="replace")
                raise GuardiumApiError(f"Guardium API returned HTTP {exc.code}: {detail}") from exc
            except (URLError, TimeoutError) as exc:
                if attempt >= self.retries:
                    raise GuardiumApiError(f"Guardium API request failed after retries: {exc}") from exc
                LOG.warning("Guardium API request failed; retrying attempt %d", attempt + 1)
                time.sleep(2**attempt)