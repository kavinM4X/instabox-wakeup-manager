#!/usr/bin/env bash
# ==============================================================================
# InstaBox Wakeup Manager - Manual Resume Operator
# ==============================================================================
# Performs a legitimate manual wake-up of a paused InstaBox machine via:
#   instabox resume "$MACHINE" --no-wait
#
# Process:
#   1. Validates configuration and credentials.
#   2. Inspects current machine lifecycle status.
#   3. If already RUNNING: skips resume, logs info, and exits 0.
#   4. If PAUSED: sends legitimate resume request with --no-wait.
#   5. If OTHER (stopped/error): safely fails without guessing.
#
# Exit Codes:
#   0 - Success (already running or resume request sent successfully).
#   1 - Configuration validation error.
#   2 - Authentication / API key authorization error.
#   3 - Machine not found.
#   4 - Machine in unsupported state (aborted for safety).
#   5 - Resume execution failed after retries.
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Run configuration validation
"${SCRIPT_DIR}/validate-config.sh" || exit 1

MACHINE_NAME="${INSTABOX_MACHINE:-test-app}"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo ""
echo "=== [InstaBox Wakeup Manager] Manual Resume Operation ==="
echo "Timestamp: ${TIMESTAMP}"
echo "Machine:   ${MACHINE_NAME}"

# 2. Check current machine state first
echo "Checking current machine state..."
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
        if [[ "${LS_OUTPUT}" =~ [Uu]nauthorized|[Ff]orbidden|[Ii]nvalid[[:space:]]API[[:space:]]key|401|403 ]]; then
            echo "ERROR: Authentication failed during 'instabox ls'. Check your INSTABOX_API_KEY." >&2
            exit 2
        fi
        if [[ ${ATTEMPT} -le ${MAX_RETRIES} ]]; then
            echo "Warning: 'instabox ls --json' failed (attempt ${ATTEMPT}/${MAX_RETRIES}). Retrying in ${RETRY_DELAY}s..."
            sleep "${RETRY_DELAY}"
        else
            echo "ERROR: Unable to inspect machine status before resume (exit code ${EXIT_CODE})." >&2
            exit 5
        fi
    fi
done

# 3. Parse machine state
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
    echo "ERROR: Machine '${MACHINE_NAME}' was not found in InstaBox machine list." >&2
    exit 3
fi

CURRENT_STATUS=""
if command -v jq >/dev/null 2>&1; then
    CURRENT_STATUS="$(echo "${MACHINE_JSON}" | jq -r '.status // empty' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
    CURRENT_STATUS="$(echo "${MACHINE_JSON}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('status', ''))" 2>/dev/null || true)"
fi

CURRENT_STATUS="$(echo "${CURRENT_STATUS}" | tr '[:upper:]' '[:lower:]')"
echo "Current Machine State: ${CURRENT_STATUS^^}"

ACTION_TAKEN="none"
OPERATION_RESULT=""

case "${CURRENT_STATUS}" in
    "running")
        echo "✓ Machine '${MACHINE_NAME}' is ALREADY RUNNING. No resume action required."
        ACTION_TAKEN="none"
        OPERATION_RESULT="Already running; no action required."
        ;;
    "paused")
        echo "Machine '${MACHINE_NAME}' is PAUSED. Dispatching legitimate resume request..."
        
        # Execute verified command: instabox resume "$MACHINE_NAME" --no-wait
        RESUME_ATTEMPT=0
        RESUME_SUCCESS=false
        RESUME_OUTPUT=""

        while [[ ${RESUME_ATTEMPT} -le ${MAX_RETRIES} ]]; do
            RESUME_ATTEMPT=$((RESUME_ATTEMPT + 1))
            if RESUME_OUTPUT="$(instabox resume "${MACHINE_NAME}" --no-wait 2>&1)"; then
                RESUME_SUCCESS=true
                break
            else
                # Check for authentication failure
                if [[ "${RESUME_OUTPUT}" =~ [Uu]nauthorized|[Ff]orbidden|[Ii]nvalid[[:space:]]API[[:space:]]key|401|403 ]]; then
                    echo "ERROR: Authentication failed during resume. Ensure INSTABOX_API_KEY has 'machines:write' scope." >&2
                    exit 2
                fi
                if [[ ${RESUME_ATTEMPT} -le ${MAX_RETRIES} ]]; then
                    echo "Warning: Resume attempt ${RESUME_ATTEMPT} failed. Retrying in ${RETRY_DELAY}s..."
                    sleep "${RETRY_DELAY}"
                fi
            fi
        done

        if [[ "${RESUME_SUCCESS}" == "true" ]]; then
            echo "✓ Resume request successfully sent for '${MACHINE_NAME}' (--no-wait)."
            ACTION_TAKEN="resumed"
            OPERATION_RESULT="Resume request successfully sent."
            if [[ -n "${RESUME_OUTPUT}" ]]; then
                echo "CLI Response: ${RESUME_OUTPUT}" | sed 's/[A-Za-z0-9_-]\{30,\}/[REDACTED]/g'
            fi
        else
            echo "ERROR: Failed to resume '${MACHINE_NAME}' after ${RESUME_ATTEMPT} attempts." >&2
            echo "${RESUME_OUTPUT}" | sed 's/[A-Za-z0-9_-]\{30,\}/[REDACTED]/g' >&2
            exit 5
        fi
        ;;
    *)
        echo "ERROR: Machine '${MACHINE_NAME}' is in unsupported state '${CURRENT_STATUS^^}'." >&2
        echo "Safe abort: InstaBox Wakeup Manager only resumes 'paused' machines. Manual verification required." >&2
        ACTION_TAKEN="aborted"
        OPERATION_RESULT="Aborted due to unsupported state: ${CURRENT_STATUS^^}"
        
        if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
            cat <<EOF >> "${GITHUB_STEP_SUMMARY}"
## ⚠️ InstaBox Manual Resume Aborted

| Property | Value |
| :--- | :--- |
| **Machine Name** | \`${MACHINE_NAME}\` |
| **Current State** | \`${CURRENT_STATUS^^}\` |
| **Action** | Aborted (Safe Guard) |
| **Reason** | Machine is not paused. Only paused machines can be resumed. |
EOF
        fi
        exit 4
        ;;
esac

# 4. GitHub Actions Output & Step Summary
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "previous_status=${CURRENT_STATUS}" >> "${GITHUB_OUTPUT}"
    echo "action_taken=${ACTION_TAKEN}" >> "${GITHUB_OUTPUT}"
    echo "machine_name=${MACHINE_NAME}" >> "${GITHUB_OUTPUT}"
    echo "timestamp=${TIMESTAMP}" >> "${GITHUB_OUTPUT}"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    STATUS_ICON="✅"
    if [[ "${ACTION_TAKEN}" == "none" ]]; then
        STATUS_ICON="ℹ️"
    fi

    cat <<EOF >> "${GITHUB_STEP_SUMMARY}"
## ${STATUS_ICON} InstaBox Resume Operation Summary

| Property | Value |
| :--- | :--- |
| **Machine Name** | \`${MACHINE_NAME}\` |
| **Initial Status** | \`${CURRENT_STATUS^^}\` |
| **Action Taken** | \`${ACTION_TAKEN}\` |
| **Result** | ${OPERATION_RESULT} |
| **Timestamp** | \`${TIMESTAMP}\` |
| **Execution Mode** | Asynchronous (\`--no-wait\`) |

> 🛡️ **Platform Policy Notice**: Resume requests are triggered exclusively on legitimate manual triggers. Automated keep-alive loops and artificial load generators are strictly prohibited.
EOF
fi

echo "=== Manual Resume Operation Completed Successfully ==="
exit 0

