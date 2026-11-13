#!/usr/bin/env bash
# ==============================================================================
# InstaBox Wakeup Manager - Configuration Validator
# ==============================================================================
# Validates the execution environment, required environment variables,
# and CLI tool availability before any operations run.
#
# Exit Codes:
#   0 - Success: Environment and configuration are valid.
#   1 - Missing or invalid required environment variables.
#   2 - InstaBox CLI not installed or not in PATH.
# ==============================================================================

set -Eeuo pipefail

echo "=== [InstaBox Wakeup Manager] Validating Configuration ==="

# 1. Check InstaBox CLI installation
if ! command -v instabox >/dev/null 2>&1; then
    echo "ERROR: 'instabox' CLI is not installed or not found in PATH." >&2
    echo "" >&2
    echo "To install InstaBox CLI:" >&2
    echo "  Official npm package:  npm install -g instabox" >&2
    echo "  Official script:       curl -fsSL https://instabox.sh/install.sh | bash" >&2
    echo "" >&2
    echo "Ensure the CLI binary is available in your PATH." >&2
    exit 2
fi

CLI_VERSION="$(instabox --version 2>/dev/null || echo "unknown")"
echo "✓ InstaBox CLI detected: version ${CLI_VERSION}"

# 2. Check INSTABOX_API_KEY
if [[ -z "${INSTABOX_API_KEY:-}" ]]; then
    echo "ERROR: INSTABOX_API_KEY environment variable is not set or empty." >&2
    echo "" >&2
    echo "Troubleshooting:" >&2
    echo "  - In GitHub Actions: Add the repository secret 'INSTABOX_API_KEY'." >&2
    echo "  - In Local Testing: Set INSTABOX_API_KEY in your shell or .env file." >&2
    echo "  - Required Scopes: 'machines:read' for status checks, 'machines:write' for manual resume." >&2
    echo "  - Security Warning: Never hardcode or commit your API key." >&2
    exit 1
fi

# Sanity check: Ensure key isn't using placeholder text
if [[ "${INSTABOX_API_KEY}" == "your_instabox_api_key_here" || "${INSTABOX_API_KEY}" == *"placeholder"* ]]; then
    echo "ERROR: INSTABOX_API_KEY appears to contain placeholder text. Please provide a valid key." >&2
    exit 1
fi

echo "✓ INSTABOX_API_KEY is configured (length: ${#INSTABOX_API_KEY} chars, value masked)."

# 3. Check INSTABOX_MACHINE
MACHINE_NAME="${INSTABOX_MACHINE:-test-app}"
if [[ -z "${MACHINE_NAME}" ]]; then
    echo "ERROR: Target machine name is empty." >&2
    echo "Please set INSTABOX_MACHINE (e.g. 'test-app')." >&2
    exit 1
fi

echo "✓ Target machine configured: '${MACHINE_NAME}'"

# 4. Optional API Base URL
API_URL="${INSTABOX_API_URL:-https://api.instabox.sh}"
echo "✓ API Endpoint: ${API_URL}"

echo "=== Configuration Validation PASSED ==="
exit 0

