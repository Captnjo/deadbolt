#!/usr/bin/env bash
# Integration test for the Deadbolt Intent API.
# Prerequisites: Deadbolt wallet app running with API server on port 9876.
#
# Usage:
#   ./tests/test_intent_api.sh [API_TOKEN]
#
# If no token is provided, reads from ~/.deadbolt/config.json.

set -euo pipefail

BASE_URL="http://127.0.0.1:9876/api/v1"
PASS=0
FAIL=0
SKIP=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Resolve API token
if [ -n "${1:-}" ]; then
    TOKEN="$1"
elif [ -f "$HOME/.deadbolt/config.json" ]; then
    TOKEN=$(python3 -c "import json; print(json.load(open('$HOME/.deadbolt/config.json')).get('apiToken', ''))" 2>/dev/null || echo "")
else
    TOKEN=""
fi

if [ -z "$TOKEN" ]; then
    echo -e "${RED}ERROR: No API token. Pass as argument or configure in ~/.deadbolt/config.json${NC}"
    exit 1
fi

AUTH="Authorization: Bearer $TOKEN"

pass() {
    echo -e "  ${GREEN}PASS${NC}: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "  ${RED}FAIL${NC}: $1 — $2"
    FAIL=$((FAIL + 1))
}

skip() {
    echo -e "  ${YELLOW}SKIP${NC}: $1 — $2"
    SKIP=$((SKIP + 1))
}

check_status() {
    local desc="$1"
    local expected_code="$2"
    local actual_code="$3"
    if [ "$actual_code" == "$expected_code" ]; then
        pass "$desc"
    else
        fail "$desc" "expected HTTP $expected_code, got $actual_code"
    fi
}

echo "========================================"
echo " Deadbolt Intent API Integration Test"
echo "========================================"
echo "Base URL: $BASE_URL"
echo "Token:    ${TOKEN:0:12}..."
echo ""

# -------------------------------------------------------------------
# Test 1: Health check (no auth)
# -------------------------------------------------------------------
echo "--- Health Check ---"
HTTP_CODE=$(curl -s -o /tmp/db_health.json -w "%{http_code}" "$BASE_URL/health")
check_status "GET /health returns 200" "200" "$HTTP_CODE"

STATUS=$(python3 -c "import json; print(json.load(open('/tmp/db_health.json')).get('status', ''))" 2>/dev/null || echo "")
if [ "$STATUS" == "ok" ]; then
    pass "Health status is 'ok'"
else
    fail "Health status is 'ok'" "got '$STATUS'"
fi

# -------------------------------------------------------------------
# Test 2: Auth required
# -------------------------------------------------------------------
echo ""
echo "--- Authentication ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/wallet")
check_status "GET /wallet without auth returns 401" "401" "$HTTP_CODE"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer bad_token" "$BASE_URL/wallet")
check_status "GET /wallet with bad token returns 401" "401" "$HTTP_CODE"

# -------------------------------------------------------------------
# Test 3: Query endpoints
# -------------------------------------------------------------------
echo ""
echo "--- Query Endpoints ---"

HTTP_CODE=$(curl -s -o /tmp/db_wallet.json -w "%{http_code}" -H "$AUTH" "$BASE_URL/wallet")
check_status "GET /wallet returns 200" "200" "$HTTP_CODE"

HTTP_CODE=$(curl -s -o /tmp/db_balance.json -w "%{http_code}" -H "$AUTH" "$BASE_URL/balance")
check_status "GET /balance returns 200" "200" "$HTTP_CODE"

HTTP_CODE=$(curl -s -o /tmp/db_tokens.json -w "%{http_code}" -H "$AUTH" "$BASE_URL/tokens")
check_status "GET /tokens returns 200" "200" "$HTTP_CODE"

HTTP_CODE=$(curl -s -o /tmp/db_price.json -w "%{http_code}" -H "$AUTH" "$BASE_URL/price?mint=So11111111111111111111111111111111111111112")
check_status "GET /price?mint=SOL returns 200" "200" "$HTTP_CODE"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH" "$BASE_URL/price")
check_status "GET /price without mint returns 400" "400" "$HTTP_CODE"

HTTP_CODE=$(curl -s -o /tmp/db_history.json -w "%{http_code}" -H "$AUTH" "$BASE_URL/history?limit=5")
check_status "GET /history returns 200" "200" "$HTTP_CODE"

# -------------------------------------------------------------------
# Test 4: Submit intent (send_sol)
# -------------------------------------------------------------------
echo ""
echo "--- Submit Intent ---"
INTENT_BODY='{
    "type": "send_sol",
    "params": {
        "recipient": "11111111111111111111111111111111",
        "amount": 1000000
    },
    "metadata": {
        "agent_id": "test-script",
        "reason": "Integration test: send 0.001 SOL"
    }
}'

HTTP_CODE=$(curl -s -o /tmp/db_intent.json -w "%{http_code}" \
    -X POST \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d "$INTENT_BODY" \
    "$BASE_URL/intent")
check_status "POST /intent returns 200" "200" "$HTTP_CODE"

REQUEST_ID=$(python3 -c "import json; print(json.load(open('/tmp/db_intent.json')).get('requestId', json.load(open('/tmp/db_intent.json')).get('request_id', '')))" 2>/dev/null || echo "")
if [ -n "$REQUEST_ID" ]; then
    pass "Response contains request_id: $REQUEST_ID"
else
    fail "Response contains request_id" "missing from response"
fi

INTENT_STATUS=$(python3 -c "import json; print(json.load(open('/tmp/db_intent.json')).get('status', ''))" 2>/dev/null || echo "")
if [ "$INTENT_STATUS" == "pending_approval" ]; then
    pass "Intent status is 'pending_approval'"
else
    fail "Intent status is 'pending_approval'" "got '$INTENT_STATUS'"
fi

# -------------------------------------------------------------------
# Test 5: Check intent status
# -------------------------------------------------------------------
echo ""
echo "--- Intent Status ---"
if [ -n "$REQUEST_ID" ]; then
    HTTP_CODE=$(curl -s -o /tmp/db_status.json -w "%{http_code}" -H "$AUTH" "$BASE_URL/status/$REQUEST_ID")
    check_status "GET /status/$REQUEST_ID returns 200" "200" "$HTTP_CODE"

    STATUS_VAL=$(python3 -c "import json; print(json.load(open('/tmp/db_status.json')).get('status', ''))" 2>/dev/null || echo "")
    if [ "$STATUS_VAL" == "pending_approval" ] || [ "$STATUS_VAL" == "rejected" ] || [ "$STATUS_VAL" == "confirmed" ]; then
        pass "Status value is valid: '$STATUS_VAL'"
    else
        fail "Status value is valid" "got '$STATUS_VAL'"
    fi
else
    skip "Status check" "no request_id from previous test"
fi

# Check nonexistent request
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH" "$BASE_URL/status/req_nonexistent")
check_status "GET /status/nonexistent returns 404" "404" "$HTTP_CODE"

# -------------------------------------------------------------------
# Test 6: Invalid intent body
# -------------------------------------------------------------------
echo ""
echo "--- Error Handling ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d '{"invalid": true}' \
    "$BASE_URL/intent")
check_status "POST /intent with bad body returns 400" "400" "$HTTP_CODE"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d 'not json' \
    "$BASE_URL/intent")
check_status "POST /intent with non-JSON returns 400" "400" "$HTTP_CODE"

# -------------------------------------------------------------------
# Test 7: Subscribe endpoint (long-poll)
# -------------------------------------------------------------------
echo ""
echo "--- Subscribe Endpoint ---"
HTTP_CODE=$(curl -s -o /tmp/db_subscribe.json -w "%{http_code}" -H "$AUTH" "$BASE_URL/subscribe?since=0&timeout=2")
check_status "GET /subscribe returns 200" "200" "$HTTP_CODE"

HAS_UPDATES=$(python3 -c "import json; d=json.load(open('/tmp/db_subscribe.json')); print('yes' if 'updates' in d else 'no')" 2>/dev/null || echo "no")
if [ "$HAS_UPDATES" == "yes" ]; then
    pass "Subscribe response contains 'updates' array"
else
    fail "Subscribe response contains 'updates' array" "missing"
fi

HAS_TIME=$(python3 -c "import json; d=json.load(open('/tmp/db_subscribe.json')); print('yes' if 'server_time' in d else 'no')" 2>/dev/null || echo "no")
if [ "$HAS_TIME" == "yes" ]; then
    pass "Subscribe response contains 'server_time'"
else
    fail "Subscribe response contains 'server_time'" "missing"
fi

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo ""
echo "========================================"
echo " Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC}"
echo "========================================"
echo ""
echo "NOTE: The send_sol intent is now pending approval in the app."
echo "      Open the app and approve/reject it to complete the test flow."

if [ $FAIL -gt 0 ]; then
    exit 1
fi
