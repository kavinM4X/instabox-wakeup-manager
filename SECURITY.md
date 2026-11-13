# Security & Platform Compliance Policy

## 1. Security Architecture & Threat Model

**InstaBox Wakeup Manager** is designed with security and compliance as foundational principles. It interfaces with the official InstaBox API (`https://api.instabox.sh`) and CLI via authenticated requests from isolated GitHub Actions runners or local developer environments.

### Core Security Guarantees
- **Zero Secret Exposure**: Secrets and API tokens are never printed, stored in logs, or checked into version control.
- **Strict Input Masking**: Output sanitization filters scrub long alphanumeric tokens (`sed 's/[A-Za-z0-9_-]\{30,\}/[REDACTED]/g'`) in scripts, and GitHub Actions automatically masks secrets.
- **Least-Privilege Principle**: GitHub Actions workflows run with minimal read-only token permissions (`permissions: contents: read`).
- **Fail-Safe Operation**: If CLI responses are malformed or ambiguous, scripts fail safely rather than guessing or performing unintended actions.

---

## 2. API Key Management & Least Privilege Scopes

When creating API keys in the InstaBox dashboard or CLI, configure key scopes strictly according to intended usage:

| Scope | Required For | Permissions Granted |
| :--- | :--- | :--- |
| `machines:read` | `check-machine.yml` & `scripts/check-machine.sh` | Read-only listing and status query of machines (`instabox ls`). Cannot modify machine state. |
| `machines:write` | `manual-resume.yml` & `scripts/resume-machine.sh` | Machine lifecycle operations (`instabox resume`). |

> [!TIP]
> If you only run status monitoring, generate an API key with **only** the `machines:read` scope. For manual resume capabilities, add `machines:write`.

---

## 3. Secret Rotation and Revocation Procedure

If an API key is suspected to be compromised, or as part of periodic security rotation:

### Step 1: Generate a New API Key
1. Sign in to your InstaBox dashboard or use the CLI:
   ```bash
   instabox auth key create --name "github-actions-wakeup-mgr-$(date +%Y%m%d)" --scopes machines:read,machines:write
   ```
2. Copy the newly generated key immediately.

### Step 2: Update GitHub Repository Secret
1. Navigate to your repository on GitHub: `https://github.com/<owner>/instabox-wakeup-manager`.
2. Go to **Settings** > **Secrets and variables** > **Actions**.
3. Under **Repository secrets**, locate `INSTABOX_API_KEY`.
4. Click the edit pencil icon, paste the new key value, and click **Update secret**.

### Step 3: Revoke the Old API Key
1. In the InstaBox dashboard or via CLI:
   ```bash
   instabox auth key revoke <old-key-id>
   ```
2. Verify that the old key is immediately disabled.

---

## 4. Platform Policy & Ethical Usage Compliance

> [!IMPORTANT]
> **InstaBox Wakeup Manager complies strictly with InstaBox Terms of Service and platform limits:**
>
> 1. **No Auto-Pause Circumvention**: Free-tier machines are subject to automatic pausing during idle periods. This tool **does not** defeat, disable, or circumvent auto-pause mechanisms.
> 2. **No Artificial Activity / Keep-Alive Tricks**: The project does not introduce synthetic CPU load, fake user activity, automated periodic network pings, or background infinite loops designed to fool idle detection algorithms.
> 3. **Non-Intrusive Monitoring**: The 16-minute scheduled monitor workflow executes read-only checks (`instabox ls`). It **never** automatically resumes a paused machine on a cron schedule.
> 4. **Legitimate Manual Wakeup**: Resume operations are triggered exclusively via explicit, intentional `workflow_dispatch` manual actions initiated by authorized repository collaborators.

---

## 5. Reporting Vulnerabilities

If you discover any security vulnerability or risk within this repository:
- Please open a private security advisory on GitHub (**Security** tab > **Advisories** > **Report a vulnerability**).
- Do not disclose security vulnerabilities in public issues or discussion forums.

