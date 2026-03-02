"""Protocol definitions for Bridge ↔ Swift app communication.

The bridge communicates with the Swift app's embedded HTTP server using:

1. **HTTP forwarding** (primary path): Agent requests arrive at the bridge,
   which forwards them to the Swift app via httpx and returns the response.

2. **Long-polling** (status updates): The bridge polls GET /api/v1/subscribe
   to receive near-real-time status changes without the agent needing to poll.

## Intent Lifecycle

    Agent → POST /intent → Bridge → POST /intent → Swift App
                                                      ↓
                                              (user sees modal)
                                                      ↓
    Agent ← GET /status  ← Bridge ← subscribe  ← Swift App
             (or poll)

## Status Flow

    pending_approval → building → signing → submitted → confirmed
                                                      → failed
                   → rejected (user declined)

## Subscribe Protocol

    GET /api/v1/subscribe?since=<unix_timestamp>&timeout=<seconds>

    Response:
    {
        "updates": [
            {
                "request_id": "req_abc123",
                "status": "confirmed",
                "signature": "5xYz...",
                "error": "",
                "updated_at": "1709161200.123"
            }
        ],
        "server_time": "1709161230.456"
    }

    - `since`: Unix timestamp; only return updates after this time
    - `timeout`: Max seconds to wait for updates (long-poll); default 30, max 60
    - `server_time`: Use as `since` for the next poll to avoid gaps
    - Empty `updates` array means timeout with no changes
"""

# Message type constants for extensibility
MSG_INTENT_SUBMIT = "intent_submit"
MSG_STATUS_UPDATE = "status_update"
MSG_INTENT_RESPONSE = "intent_response"

# Status values matching Swift IntentStatus
STATUS_PENDING_APPROVAL = "pending_approval"
STATUS_BUILDING = "building"
STATUS_SIGNING = "signing"
STATUS_SUBMITTED = "submitted"
STATUS_CONFIRMED = "confirmed"
STATUS_REJECTED = "rejected"
STATUS_FAILED = "failed"

TERMINAL_STATUSES = {STATUS_CONFIRMED, STATUS_REJECTED, STATUS_FAILED}


def is_terminal(status: str) -> bool:
    """Check if a status is terminal (no further updates expected)."""
    return status in TERMINAL_STATUSES
