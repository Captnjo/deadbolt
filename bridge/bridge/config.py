"""Configuration loading from ~/.deadbolt/config.json."""

import json
import os
from pathlib import Path
from dataclasses import dataclass, field


@dataclass
class BridgeConfig:
    """Bridge configuration."""

    api_token: str = ""
    upstream_url: str = "http://127.0.0.1:9876"
    bridge_port: int = 9877
    bridge_host: str = "0.0.0.0"

    @classmethod
    def load(cls, token_override: str | None = None) -> "BridgeConfig":
        """Load config from ~/.deadbolt/config.json, with CLI overrides."""
        config = cls()

        config_path = Path.home() / ".deadbolt" / "config.json"
        if config_path.exists():
            try:
                data = json.loads(config_path.read_text())
                if "apiToken" in data and data["apiToken"]:
                    config.api_token = data["apiToken"]
            except (json.JSONDecodeError, KeyError):
                pass

        if token_override:
            config.api_token = token_override

        # Environment variable overrides
        if token := os.environ.get("DEADBOLT_API_TOKEN"):
            config.api_token = token
        if url := os.environ.get("DEADBOLT_UPSTREAM_URL"):
            config.upstream_url = url
        if port := os.environ.get("DEADBOLT_BRIDGE_PORT"):
            config.bridge_port = int(port)

        return config
