"""Main entry point for the Deadbolt Bridge service."""

import argparse
import logging
import uvicorn
from fastapi import FastAPI
from bridge.config import BridgeConfig
from bridge.routes import router


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


def create_app(config: BridgeConfig | None = None) -> FastAPI:
    """Create the FastAPI application."""
    if config is None:
        config = BridgeConfig.load()

    app = FastAPI(
        title="Deadbolt Bridge",
        description="External proxy for the Deadbolt wallet Intent API",
        version="0.1.0",
    )
    app.state.config = config
    app.include_router(router)
    return app


def cli():
    """CLI entry point."""
    parser = argparse.ArgumentParser(description="Deadbolt Bridge Service")
    parser.add_argument("--port", type=int, default=9877, help="Port to listen on (default: 9877)")
    parser.add_argument("--host", type=str, default="0.0.0.0", help="Host to bind to (default: 0.0.0.0)")
    parser.add_argument("--token", type=str, default=None, help="API token override")
    parser.add_argument("--upstream", type=str, default=None, help="Upstream Swift app URL")
    args = parser.parse_args()

    config = BridgeConfig.load(token_override=args.token)
    config.bridge_port = args.port
    config.bridge_host = args.host
    if args.upstream:
        config.upstream_url = args.upstream

    if not config.api_token:
        logger.warning("No API token configured. Set one in ~/.deadbolt/config.json or use --token")

    logger.info("Starting Deadbolt Bridge on %s:%d", config.bridge_host, config.bridge_port)
    logger.info("Forwarding to upstream: %s", config.upstream_url)

    app = create_app(config)
    uvicorn.run(app, host=config.bridge_host, port=config.bridge_port)


if __name__ == "__main__":
    cli()
