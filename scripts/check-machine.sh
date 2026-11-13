#!/usr/bin/env bash
# ==============================================================================
# InstaBox Wakeup Manager - Machine Status Checker
# ==============================================================================
# Non-intrusive status checker for InstaBox machines.
# Inspects machine lifecycle status using 'instabox ls --json'.
#
# POLICY:
#   Does NOT resume, poke, or alter the machine state.
#   Respects auto-pause policy and platform runtime limits.
#
# Exit Codes:
#   0 - Machine checked successfully.
#   1 - Configuration validation failure.
#   2 - InstaBox CLI execution error.
#   3 - Machine not found.
#   4 - Ambiguous or unexpected output.
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Run configuration validation
"${SCRIPT_DIR}/validate-config.sh" || exit 1

MACHINE_NAME="${INSTABOX_MACHINE:-test-app}"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo ""
echo "=== [InstaBox Wakeup Manager] Checking Machine Status ==="
echo "Timestamp: ${TIMESTAMP}"
echo "Machine:   ${MACHINE_NAME}"

# 2. Query machine status with bounded retry for transient network issues
MAX_RETRIES=2
RETRY_DELAY=3
ATTEMPT=0
LS_OUTPUT=""

while [[ ${ATTEMPT} -le ${MAX_RETRIES} ]]; do
    ATTEMPT=$((ATTEMPT + 1))
    if LS_OUTPUT="$(instabox ls --json 2>&1)"; then
        break
    else
        EXIT_CODE=$?
        # Check for authentication failure
        if [[ "${LS_OUTPUT}" =~ [Uu]nauthorized|[Ff]orbidden|[Ii]nvalid[[:space:]]API[[:space:]]key|401|403 ]]; then
            echo "ERROR: Authentication failed during 'instabox ls'. Check your INSTABOX_API_KEY." >&2
            exit 2
        fi
        if [[ ${ATTEMPT} -le ${MAX_RETRIES} ]]; then
            echo "Warning: 'instabox ls --json' failed (attempt ${ATTEMPT}/${MAX_RETRIES}). Retrying in ${RETRY_DELAY}s..."
            sleep "${RETRY_DELAY}"
        else
            echo "ERROR: Failed to list InstaBox machines after ${ATTEMPT} attempts (exit code ${EXIT_CODE})." >&2
            echo "Output:" >&2
            echo "${LS_OUTPUT}" | sed 's/[A-Za-z0-9_-]\{30,\}/[REDACTED]/g' >&2
            exit 2
        fi
    fi
done

# 3. Parse JSON output safely
MACHINE_JSON=""
if command -v jq >/dev/null 2>&1; then
    MACHINE_JSON="$(echo "${LS_OUTPUT}" | jq -c ".[] | select(.name == \"${MACHINE_NAME}\")" 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
    MACHINE_JSON="$(echo "${LS_OUTPUT}" | python3 -c "import sys, json
try:
    data = json.load(sys.stdin)
    for m in data:
        if m.get('name') == '${MACHINE_NAME}':
            print(json.dumps(m))
            break
except Exception:
    sys.exit(1)" 2>/dev/null || true)"
fi

if [[ -z "${MACHINE_JSON}" ]]; then
    echo "ERROR: Machine '${MACHINE_NAME}' was not found in the InstaBox machine list." >&2
    echo "Available machines:" >&2
    if command -v jq >/dev/null 2>&1; then
        echo "${LS_OUTPUT}" | jq -r '.[].name' 2>/dev/null || true
    fi
    exit 3
fi

# Extract status field
MACHINE_STATUS=""
if command -v jq >/dev/null 2>&1; then
    MACHINE_STATUS="$(echo "${MACHINE_JSON}" | jq -r '.status // empty' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
    MACHINE_STATUS="$(echo "${MACHINE_JSON}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('status', ''))" 2>/dev/null || true)"
fi

MACHINE_STATUS="$(echo "${MACHINE_STATUS}" | tr '[:upper:]' '[:lower:]')"

if [[ -z "${MACHINE_STATUS}" ]]; then
    echo "ERROR: Could not determine machine status from CLI response." >&2
    echo "Safe abort: Output was ambiguous." >&2
    exit 4
fi

echo "Status:    ${MACHINE_STATUS^^}"
echo "Result:    Status successfully queried."
echo "Policy:    Read-only check. Machine state was not modified."

# 4. Export to GitHub Actions outputs and step summary if present
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "status=${MACHINE_STATUS}" >> "${GITHUB_OUTPUT}"
    echo "machine_name=${MACHINE_NAME}" >> "${GITHUB_OUTPUT}"
    echo "checked_at=${TIMESTAMP}" >> "${GITHUB_OUTPUT}"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    STATUS_BADGE="🟢"
    if [[ "${MACHINE_STATUS}" == "paused" ]]; then
        STATUS_BADGE="⏸️"
    elif [[ "${MACHINE_STATUS}" != "running" ]]; then
        STATUS_BADGE="⚪"
    fi

    cat <<EOF >> "${GITHUB_STEP_SUMMARY}"
## ${STATUS_BADGE} InstaBox Machine Status Report

| Property | Value |
| :--- | :--- |
| **Machine Name** | \`${MACHINE_NAME}\` |
| **Status** | **\`${MACHINE_STATUS^^}\`** |
| **Checked At** | \`${TIMESTAMP}\` |
| **Action Taken** | None (Monitoring Only) |

> ℹ️ **Compliance Notice**: This scheduled or manual workflow monitors availability without modifying machine state or bypassing idle auto-pause.
EOF
fi

exit 0

