#!/usr/bin/env bash
# =============================================================
# notify_admin.sh  –  Email admin after AI auto-fix
# =============================================================
# Usage:
#   bash notify_admin.sh <ADMIN_EMAIL> <BUILD_NUMBER> <FIX_SUMMARY_FILE> <BUILD_URL>
# =============================================================

set -euo pipefail

ADMIN_EMAIL="${1:?'Missing ADMIN_EMAIL'}"
BUILD_NUMBER="${2:?'Missing BUILD_NUMBER'}"
FIX_SUMMARY_FILE="${3:?'Missing FIX_SUMMARY_FILE'}"
BUILD_URL="${4:-N/A}"

HOSTNAME=$(hostname -f 2>/dev/null || hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
FIX_CONTENT=$(cat "${FIX_SUMMARY_FILE}" 2>/dev/null || echo "No fix summary available.")

SUBJECT="✅ [Jenkins AI] Error Fixed – Build #${BUILD_NUMBER} on ${HOSTNAME}"

BODY=$(cat <<EMAIL
Jenkins AI Auto-Remediation Report
====================================
Timestamp   : ${TIMESTAMP}
Build       : #${BUILD_NUMBER}
Build URL   : ${BUILD_URL}
Server      : ${HOSTNAME}

The Gemini AI assistant has successfully detected and fixed errors
in your DevSecOps pipeline. Changes have been committed and pushed
to your Git repository. A new build has been triggered automatically.

---- AI Fix Summary ----
${FIX_CONTENT}
------------------------

Action Required:
  - Review the changes in your Git repository
  - Monitor the new build triggered automatically
  - If the fix looks incorrect, revert the commit and run the pipeline again

This message was sent automatically by Jenkins AI Pipeline Bot.
EMAIL
)

echo "📧 Sending admin notification to: ${ADMIN_EMAIL}"

# ── Try mailx (most common on Ubuntu) ────────────────────────────────────────
if command -v mailx &>/dev/null; then
    echo "${BODY}" | mailx -s "${SUBJECT}" "${ADMIN_EMAIL}"
    echo "✅ Email sent via mailx."
    exit 0
fi

# ── Try sendmail ──────────────────────────────────────────────────────────────
if command -v sendmail &>/dev/null; then
    {
        echo "To: ${ADMIN_EMAIL}"
        echo "Subject: ${SUBJECT}"
        echo "Content-Type: text/plain"
        echo ""
        echo "${BODY}"
    } | sendmail -t
    echo "✅ Email sent via sendmail."
    exit 0
fi

# ── Try curl with a Slack webhook (fallback if SLACK_WEBHOOK is set) ──────────
if [ -n "${SLACK_WEBHOOK:-}" ]; then
    SLACK_MSG=$(cat <<SLACK
{
  "text": "*${SUBJECT}*\n\`\`\`${FIX_CONTENT}\`\`\`\nBuild URL: ${BUILD_URL}"
}
SLACK
)
    curl -s -X POST "${SLACK_WEBHOOK}" \
        -H "Content-Type: application/json" \
        -d "${SLACK_MSG}"
    echo "✅ Slack notification sent."
    exit 0
fi

# ── Fallback: print to log ────────────────────────────────────────────────────
echo "⚠️  No mail or Slack configured. Printing notification to console:"
echo "${BODY}"
echo "ℹ️  To enable email: install mailx or configure SMTP on Jenkins."
echo "   Or set SLACK_WEBHOOK env variable for Slack notifications."
