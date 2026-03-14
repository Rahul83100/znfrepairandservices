#!/usr/bin/env bash
# =============================================================
# ai_analyze.sh  –  Send scan errors to Gemini and get a report
# =============================================================
# Usage:
#   bash ai_analyze.sh <API_KEY> <ERROR_FILE> <REPORT_FILE> <mode>
#   mode: "with_errors" | "no_errors"
# =============================================================

set -euo pipefail

API_KEY="${1:?'Missing GEMINI_API_KEY'}"
ERROR_FILE="${2:?'Missing ERROR_FILE path'}"
REPORT_FILE="${3:?'Missing REPORT_FILE path'}"
MODE="${4:-with_errors}"

GEMINI_URL="https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${API_KEY}"

# ── Helper: pretty print header ──────────────────────────────────────────────
header() { echo ""; echo "==> $*"; }

header "Gemini AI Analyzer starting (mode: ${MODE})"

# ── Build prompt based on mode ────────────────────────────────────────────────
if [ "${MODE}" = "no_errors" ]; then
    PROMPT="You are a DevSecOps AI assistant embedded in a Jenkins CI/CD pipeline. \
All security scan stages (Secrets Scanning, SAST, SCA, IaC) have passed with NO errors. \
Write a SHORT, enthusiastic, emoji-rich success message (max 5 lines) to the DevOps team \
congratulating them on a clean build. Mention that all phases passed."
else
    ERROR_CONTENT=$(cat "${ERROR_FILE}" 2>/dev/null || echo "No error details available.")

    # Cap error content to avoid token limits
    ERROR_CONTENT=$(echo "${ERROR_CONTENT}" | head -c 8000)

    PROMPT="You are a senior DevSecOps AI assistant embedded in a Jenkins CI/CD pipeline. \
The pipeline has completed but the following errors were found across various security scan stages:\n\n\
${ERROR_CONTENT}\n\n\
Your task:\n\
1. Write a clear SUMMARY of what went wrong in each stage (use bullet points).\n\
2. Explain the SEVERITY of each issue (Critical / High / Medium / Low).\n\
3. Give SPECIFIC, actionable fix recommendations for each error.\n\
4. At the end, provide a numbered ACTION PLAN listing all files or config changes needed to fix these issues.\n\
5. Be concise but thorough. Use markdown formatting with emojis for readability.\n\
The output will be shown directly to the DevOps team in the Jenkins console log."
fi

# ── Call Gemini API ───────────────────────────────────────────────────────────
header "Calling Gemini API..."

# Escape the prompt for JSON
ESCAPED_PROMPT=$(printf '%s' "${PROMPT}" | python3 -c "
import sys, json
print(json.dumps(sys.stdin.read()))
" 2>/dev/null || printf '%s' "${PROMPT}" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n')

REQUEST_BODY=$(cat <<EOF
{
  "contents": [
    {
      "parts": [
        {
          "text": ${ESCAPED_PROMPT}
        }
      ]
    }
  ],
  "generationConfig": {
    "temperature": 0.4,
    "maxOutputTokens": 2048
  }
}
EOF
)

HTTP_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    -X POST "${GEMINI_URL}" \
    -H "Content-Type: application/json" \
    -d "${REQUEST_BODY}")

HTTP_BODY=$(echo "${HTTP_RESPONSE}" | sed -e 's/HTTP_STATUS:.*//')
HTTP_STATUS=$(echo "${HTTP_RESPONSE}" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')

header "Gemini API response status: ${HTTP_STATUS}"

if [ "${HTTP_STATUS}" != "200" ]; then
    echo "❌ Gemini API call failed with status ${HTTP_STATUS}:"
    echo "${HTTP_BODY}"
    # Fallback report
    cat > "${REPORT_FILE}" <<FALLBACK
❌ Gemini AI Analysis Failed (API status: ${HTTP_STATUS})

Raw error content from scan stages:
$(cat "${ERROR_FILE}" 2>/dev/null || echo "No error file found.")

Please review the Jenkins stage logs above for details.
FALLBACK
    exit 0   # Don't block the pipeline on API failure
fi

# ── Extract text from Gemini response ────────────────────────────────────────
AI_TEXT=$(echo "${HTTP_BODY}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    text = data['candidates'][0]['content']['parts'][0]['text']
    print(text)
except Exception as e:
    print(f'Failed to parse Gemini response: {e}')
    print('Raw response:')
    sys.stdin = open('/dev/stdin')
" 2>/dev/null || echo "${HTTP_BODY}" | grep -o '"text":"[^"]*"' | head -1 | sed 's/"text":"//;s/"$//')

# ── Write report ──────────────────────────────────────────────────────────────
{
    echo "============================================"
    echo "     🤖 GEMINI AI PIPELINE REPORT"
    echo "     Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================"
    echo ""
    echo "${AI_TEXT}"
    echo ""
    echo "============================================"
} > "${REPORT_FILE}"

header "Report written to ${REPORT_FILE}"
echo "✅ AI analysis complete."
