"""Long-polling client for real-time status updates from the Swift app."""

import asyncio
import logging
import time
from typing import Callable

import httpx


logger = logging.getLogger(__name__)


class StatusPoller:
    """Long-polls the Swift app's /subscribe endpoint for real-time status updates."""

    def __init__(
        self,
        upstream_url: str,
        api_token: str,
        on_status_update: Callable | None = None,
        poll_timeout: float = 30.0,
    ):
        self.upstream_url = upstream_url.rstrip("/")
        self.api_token = api_token
        self.on_status_update = on_status_update
        self.poll_timeout = poll_timeout
        self._task: asyncio.Task | None = None
        self._last_timestamp: float = time.time()

    async def start(self):
        """Start the long-polling loop."""
        self._task = asyncio.create_task(self._run())

    async def stop(self):
        """Stop the long-polling loop."""
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    async def _run(self):
        """Long-polling loop with auto-reconnect."""
        while True:
            try:
                url = (
                    f"{self.upstream_url}/api/v1/subscribe"
                    f"?since={self._last_timestamp}&timeout={int(self.poll_timeout)}"
                )
                headers = {"Authorization": f"Bearer {self.api_token}"}

                async with httpx.AsyncClient(timeout=self.poll_timeout + 10) as client:
                    resp = await client.get(url, headers=headers)

                    if resp.status_code == 200:
                        data = resp.json()
                        updates = data.get("updates", [])
                        if data.get("server_time"):
                            self._last_timestamp = float(data["server_time"])

                        for update in updates:
                            if self.on_status_update:
                                self.on_status_update(update)
                    elif resp.status_code == 401:
                        logger.error("Authentication failed with upstream. Check API token.")
                        await asyncio.sleep(30)
                    else:
                        logger.warning(
                            "Upstream subscribe returned %d. Retrying in 5s...",
                            resp.status_code,
                        )
                        await asyncio.sleep(5)

            except httpx.ConnectError:
                logger.warning("Cannot connect to upstream %s. Retrying in 5s...", self.upstream_url)
                await asyncio.sleep(5)
            except httpx.TimeoutException:
                # Normal — long-poll timed out, loop again
                pass
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.warning("Unexpected error in status poller: %s. Retrying in 5s...", e)
                await asyncio.sleep(5)
