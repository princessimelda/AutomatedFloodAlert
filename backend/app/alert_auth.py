"""Server-owned operator credentials and Supabase-verified recipient identity."""

import secrets
from dataclasses import dataclass
from uuid import UUID

import httpx
from fastapi import HTTPException, Security
from fastapi.security import APIKeyHeader, HTTPAuthorizationCredentials, HTTPBearer

OPERATOR_KEY = APIKeyHeader(name="X-FloodSafe-Key", auto_error=False)
RECIPIENT_TOKEN = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class Actor:
    id: str
    role: str


def operator(settings, *roles):
    def authenticate(supplied: str | None = Security(OPERATOR_KEY)):
        supplied = supplied or ""
        if not settings.alert_principals:
            raise HTTPException(503)
        if len(supplied) < 32 or len(supplied) > 256:
            raise HTTPException(401)
        actor = None
        for credential in settings.alert_principals.values():
            if secrets.compare_digest(supplied, credential.key.get_secret_value()):
                actor = Actor(credential.actor_id, credential.role)
        if actor is None:
            raise HTTPException(401)
        if actor.role not in roles:
            raise HTTPException(403)
        return actor

    return authenticate


def recipient(settings):
    def authenticate(credentials: HTTPAuthorizationCredentials | None = Security(RECIPIENT_TOKEN)):
        token = f"Bearer {credentials.credentials}" if credentials else ""
        if not token.startswith("Bearer ") or not 10 < len(token) < 8192:
            raise HTTPException(401)
        if (
            not settings.auth_url.startswith("https://")
            or not settings.auth_publishable_key.get_secret_value()
        ):
            raise HTTPException(503)
        try:
            response = httpx.get(
                settings.auth_url.rstrip("/") + "/auth/v1/user",
                headers={
                    "Authorization": token,
                    "apikey": settings.auth_publishable_key.get_secret_value(),
                },
                timeout=10,
                follow_redirects=False,
            )
            if response.status_code in {401, 403}:
                raise HTTPException(401)
            response.raise_for_status()
            return str(UUID(response.json()["id"]))
        except HTTPException:
            raise
        except (httpx.HTTPError, ValueError, KeyError, TypeError):
            raise HTTPException(503) from None

    return authenticate
