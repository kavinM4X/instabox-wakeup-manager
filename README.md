# InstaBox Wakeup Manager

A secure, production-grade automation suite for monitoring and legitimately waking up InstaBox cloud developer machines (`test-app`) via the official InstaBox CLI and GitHub Actions.

---

## 📋 Table of Contents
- [Overview](#overview)
- [Platform Compliance & Ethics](#platform-compliance--ethics)
- [Key Features](#key-features)
- [Project Architecture](#project-architecture)
- [GitHub Actions Configuration](#github-actions-configuration)
  - [1. Add Repository Secret (`INSTABOX_API_KEY`)](#1-add-repository-secret-instabox_api_key)
  - [2. Add Repository Variable (`INSTABOX_MACHINE`)](#2-add-repository-variable-instabox_machine)
- [Workflows Overview](#workflows-overview)
  - [1. Status Monitor (`check-machine.yml`)](#1-status-monitor-check-machineyml)
  - [2. Manual Resume (`manual-resume.yml`)](#2-manual-resume-manual-resumeyml)
- [Local Development & Script Execution](#local-development--script-execution)
- [Troubleshooting & Diagnostics](#troubleshooting--diagnostics)
- [Exit Code Reference](#exit-code-reference)
- [Security Policy](#security-policy)

---

## Overview

[InstaBox](https://instabox.sh) provides cloud Linux microVMs for software development and automated coding tasks. Under standard and free plans, idle machines automatically pause to preserve computing resources.

**InstaBox Wakeup Manager** provides:
1. **Periodic Status Monitoring**: A 16-minute scheduled read-only check to observe machine state.
2. **Intentional Manual Wakeup**: A GitHub Actions manual trigger (`workflow_dispatch`) that inspects machine status and resumes a `paused` machine using the verified CLI command:
   ```bash
   instabox resume "$INSTABOX_MACHINE" --no-wait
   ```
3. **Safety Guards**: Detects if the machine is already `running` (avoiding redundant API calls) or in an unexpected state, failing safely without guessing.

---

## 🛡️ Platform Compliance & Ethics

> [!IMPORTANT]
> **Strict Anti-Circumvention Policy**:
> - **Auto-pause is preserved**: This tool does **not** bypass, defeat, or disable InstaBox's free-plan auto-pause or runtime limits.
> - **No artificial activity**: Does **not** simulate artificial CPU load, synthetic user activity, or periodic background requests intended to evade idle timers.
> - **No automated resume loops**: Scheduled cron monitoring is strictly **read-only**. It never automatically resumes a paused machine. Resume operations are only triggered on explicit manual user request.

---

## Key Features

- **Safe Lifecycle Inspection**: Inspects machine state using verified JSON commands (`instabox ls --json`).
- **Idempotent Resume Logic**: Checks current state before triggering a resume. If already `running`, reports no action needed.
- **Asynchronous Wakeup**: Uses `--no-wait` to dispatch resume requests swiftly without holding runner threads open.
- **Hardened Security**:
  - Zero token logging or leaks.
  - Sanitizes output logs to scrub sensitive alphanumeric strings.
  - Uses least-privilege GitHub Actions permissions (`permissions: contents: read`).
  - Supports least-privilege API scopes (`machines:read` and `machines:write`).
- **Resilience**: Bounded exponential retries (up to 2 retries, 3 total attempts) for handling transient network failures.
- **Concurrency Control**: Prevents overlapping execution runs in GitHub Actions.
- **Detailed Step Summaries**: Produces rich Markdown summaries in GitHub Actions (`GITHUB_STEP_SUMMARY`).

---

## Project Architecture

```
instabox-wakeup-manager/
├── .github/
│   └── workflows/
│       ├── check-machine.yml      # 16-minute read-only status monitor & manual check
│       └── manual-resume.yml      # Manual workflow_dispatch to resume a paused machine
├── scripts/
│   ├── check-machine.sh           # Queries machine status via 'instabox ls --json'
│   ├── resume-machine.sh          # Checks state and safely triggers 'instabox resume --no-wait'
│   └── validate-config.sh         # Validates environment variables and CLI availability
├── .env.example                   # Local configuration template (never commit real secrets)
├── .gitignore                     # Git ignore rules protecting credentials and artifacts
├── README.md                      # Complete setup and operational guide
└── SECURITY.md                    # Threat model, scope guidelines, and key rotation procedures
```

---

## GitHub Actions Configuration

To enable automated workflows in your repository, configure the required secret and variable.

### 1. Add Repository Secret (`INSTABOX_API_KEY`)
1. Go to your repository on GitHub: `https://github.com/<owner>/instabox-wakeup-manager`.
2. Navigate to **Settings** > **Secrets and variables** > **Actions**.
3. Under the **Repository secrets** tab, click **New repository secret**.
4. Set:
   - **Name**: `INSTABOX_API_KEY`
   - **Secret**: Paste your InstaBox API Key (must have `machines:read` and `machines:write` scopes).
5. Click **Add secret**.

> [!NOTE]
> Never share or paste your actual API key into issues, pull requests, or chat prompts. GitHub automatically redacts known secrets from logs.

### 2. Add Repository Variable (`INSTABOX_MACHINE`)
1. In **Settings** > **Secrets and variables** > **Actions**, click the **Variables** tab.
2. Click **New repository variable**.
3. Set:
   - **Name**: `INSTABOX_MACHINE`
   - **Value**: `test-app`
4. Click **Add variable**.

---

## Workflows Overview

### 1. Status Monitor (`check-machine.yml`)
- **Trigger**: Every 16 minutes (`cron: '*/16 * * * *'`) and manual `workflow_dispatch`.
- **Purpose**: Verifies that the machine is reachable and reports its lifecycle status (`running`, `paused`, etc.).
- **Behavior**: Strictly read-only; never sends a resume command.

### 2. Manual Resume (`manual-resume.yml`)
- **Trigger**: Manual `workflow_dispatch`.
- **Inputs**:
  - `machine_name`: (Optional) Override target machine name.
  - `reason`: (Optional) Description of the work session.
- **Workflow Steps**:
  1. Validates CLI and credentials.
  2. Queries current status via `instabox ls --json`.
  3. If **`running`**: Reports status and completes without action.
  4. If **`paused`**: Executes `instabox resume "$MACHINE" --no-wait`.
  5. If **other state**: Safely aborts to prevent unintentional state changes.

---

## Local Development & Script Execution

You can run and test all scripts on any local machine (Linux, macOS, or Windows Git Bash / WSL) with the InstaBox CLI installed.

### 1. Prerequisites
- **InstaBox CLI** (version `0.8.269` or later):
  ```bash
  npm install -g instabox
  # or
  curl -fsSL https://instabox.sh/install.sh | bash
  ```
- **Bash shell** and `jq` (recommended for fast JSON parsing; Python 3 is automatically used as fallback).

### 2. Local Setup
```bash
# Clone the repository
git clone https://github.com/<owner>/instabox-wakeup-manager.git
cd instabox-wakeup-manager

# Copy the environment template
cp .env.example .env

# Edit .env with your actual API key and machine name
# (Remember: .env is ignored by git)
nano .env

# Source the environment variables
set -a; source .env; set +a
```

### 3. Run Scripts
```bash
# Ensure scripts are executable
chmod +x scripts/*.sh

# Step 1: Validate configuration
./scripts/validate-config.sh

# Step 2: Check machine status (read-only)
./scripts/check-machine.sh

# Step 3: Trigger manual resume (if paused)
./scripts/resume-machine.sh
```

---

## Troubleshooting & Diagnostics

| Symptom | Cause | Solution |
| :--- | :--- | :--- |
| `ERROR: 'instabox' CLI is not installed` | CLI binary missing from PATH. | Install via `npm install -g instabox` or check that npm global bin path is in `$PATH`. |
| `ERROR: INSTABOX_API_KEY environment variable is not set` | Missing secret or local environment variable. | In GitHub Actions, verify secret name `INSTABOX_API_KEY`. Locally, check `.env`. |
| `ERROR: Authentication failed during 'instabox ls'` (401/403) | API key expired, revoked, or lacking `machines:read`. | Re-generate API key in InstaBox dashboard with required scopes. |
| `ERROR: Machine 'test-app' was not found` | Machine name mismatch or machine was deleted. | Run `instabox ls` to verify your machine names, and update `INSTABOX_MACHINE`. |
| `ERROR: Machine is in unsupported state` | Machine is stopped or in error state. | Manual inspection needed via `instabox ls` or the web dashboard. |

---

## Exit Code Reference

All scripts follow standardized UNIX exit codes:

| Code | Meaning |
| :--- | :--- |
| `0` | Success (operation completed or verified). |
| `1` | Configuration or required environment variable error. |
| `2` | InstaBox CLI missing or CLI execution / authentication error. |
| `3` | Machine not found in InstaBox machine listing. |
| `4` | Unsupported or ambiguous machine lifecycle state. |
| `5` | Resume execution failed after bounded retries. |

---

## Security Policy

For secret rotation instructions, least-privilege scope recommendations, and vulnerability reporting procedures, see [SECURITY.md](SECURITY.md).

