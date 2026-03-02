"""Bearer token authentication middleware."""

from fastapi import Request, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from bridge.config import BridgeConfig


security = HTTPBearer()


async def verify_token(
    request: Request,
    credentials: HTTPAuthorizationCredentials = None,
) -> str:
    """Verify the bearer token matches the configured API token."""
    config: BridgeConfig = request.app.state.config

    if not config.api_token:
        raise HTTPException(status_code=500, detail="No API token configured")

    auth_header = request.headers.get("authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")

    token = auth_header[len("Bearer "):]
    if token != config.api_token:
        raise HTTPException(status_code=401, detail="Invalid API token")

    return token
