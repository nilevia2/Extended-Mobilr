from __future__ import annotations

from typing import Any, Dict, Optional

import httpx
from httpx import HTTPStatusError

from ..config import EndpointConfig


class ExtendedRESTClient:
    def __init__(self, config: EndpointConfig, timeout_seconds: float = 15.0) -> None:
        self._config = config
        self._timeout = timeout_seconds

    def _headers(self, api_key: Optional[str]) -> Dict[str, str]:
        headers: Dict[str, str] = {"Accept": "application/json"}
        if api_key:
            headers["X-Api-Key"] = api_key
        return headers

    def get_private(self, api_key: str, path: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        url = f"{self._config.api_base_url}{path}"
        with httpx.Client(timeout=self._timeout) as client:
            res = client.get(url, headers=self._headers(api_key), params=params or {})
            res.raise_for_status()
            return res.json()

    def post_private(self, api_key: str, path: str, json: Dict[str, Any]) -> Dict[str, Any]:
        url = f"{self._config.api_base_url}{path}"
        with httpx.Client(timeout=self._timeout) as client:
            res = client.post(url, headers=self._headers(api_key), json=json)
            if res.status_code >= 400:
                error_detail = res.text
                try:
                    error_json = res.json()
                    error_detail = str(error_json)
                except:
                    pass
                raise HTTPStatusError(
                    f"Extended API error {res.status_code}: {error_detail}",
                    request=res.request,
                    response=res,
                )
            res.raise_for_status()
            return res.json()


