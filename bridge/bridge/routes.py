"""API routes — forwards all requests to the Swift app's embedded server."""

import httpx
from fastapi import APIRouter, Request, Depends, HTTPException
from fastapi.responses import JSONResponse
from bridge.auth import verify_token
from bridge.config import BridgeConfig


router = APIRouter(prefix="/api/v1")


async def _forward(request: Request, method: str, path: str, body: bytes | None = None) -> JSONResponse:
    """Forward a request to the upstream Swift app."""
    config: BridgeConfig = request.app.state.config
    url = f"{config.upstream_url}/api/v1/{path}"

    headers = {}
    if auth := request.headers.get("authorization"):
        headers["Authorization"] = auth

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            if method == "GET":
                resp = await client.get(url, headers=headers, params=dict(request.query_params))
            elif method == "POST":
                headers["Content-Type"] = "application/json"
                resp = await client.post(url, headers=headers, content=body)
            else:
                raise HTTPException(status_code=405, detail="Method not allowed")

            return JSONResponse(
                status_code=resp.status_code,
                content=resp.json(),
            )
        except httpx.ConnectError:
            raise HTTPException(
                status_code=502,
                detail="Cannot connect to Deadbolt wallet app. Is it running?",
            )
        except httpx.TimeoutException:
            raise HTTPException(status_code=504, detail="Upstream timeout")


# Intent endpoints
@router.post("/intent")
async def submit_intent(request: Request, _token: str = Depends(verify_token)):
    body = await request.body()
    return await _forward(request, "POST", "intent", body)


@router.get("/status/{request_id}")
async def get_status(request: Request, request_id: str, _token: str = Depends(verify_token)):
    return await _forward(request, "GET", f"status/{request_id}")


# Query endpoints
@router.get("/wallet")
async def get_wallet(request: Request, _token: str = Depends(verify_token)):
    return await _forward(request, "GET", "wallet")


@router.get("/balance")
async def get_balance(request: Request, _token: str = Depends(verify_token)):
    return await _forward(request, "GET", "balance")


@router.get("/tokens")
async def get_tokens(request: Request, _token: str = Depends(verify_token)):
    return await _forward(request, "GET", "tokens")


@router.get("/price")
async def get_price(request: Request, _token: str = Depends(verify_token)):
    return await _forward(request, "GET", "price")


@router.get("/history")
async def get_history(request: Request, _token: str = Depends(verify_token)):
    return await _forward(request, "GET", "history")


# Subscribe (long-poll for status updates)
@router.get("/subscribe")
async def subscribe(request: Request, _token: str = Depends(verify_token)):
    config: BridgeConfig = request.app.state.config
    url = f"{config.upstream_url}/api/v1/subscribe"
    headers = {}
    if auth := request.headers.get("authorization"):
        headers["Authorization"] = auth
    # Long-poll can take up to 60s, so extend the timeout
    timeout = float(request.query_params.get("timeout", "30"))
    async with httpx.AsyncClient(timeout=timeout + 5) as client:
        try:
            resp = await client.get(url, headers=headers, params=dict(request.query_params))
            return JSONResponse(status_code=resp.status_code, content=resp.json())
        except httpx.ConnectError:
            raise HTTPException(status_code=502, detail="Cannot connect to Deadbolt wallet app. Is it running?")
        except httpx.TimeoutException:
            raise HTTPException(status_code=504, detail="Upstream timeout")


# Health check (no auth)
@router.get("/health")
async def health():
    return {"status": "ok", "service": "deadbolt-bridge"}
