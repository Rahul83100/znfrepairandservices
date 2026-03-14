#!/usr/bin/env bash
# =============================================================
# apply_fix.sh  –  Ask Gemini to fix code errors and apply patches
# =============================================================
# Usage:
#   bash apply_fix.sh <API_KEY> <ERROR_FILE> <WORKSPACE> <FIX_SUMMARY_FILE>
# =============================================================

set -euo pipefail

API_KEY="${1:?'Missing GEMINI_API_KEY'}"
ERROR_FILE="${2:?'Missing ERROR_FILE path'}"
WORKSPACE="${3:?'Missing WORKSPACE path'}"
FIX_SUMMARY="${4:?'Missing FIX_SUMMARY_FILE path'}"

GEMINI_URL="https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${API_KEY}"

echo "============================================"
echo " 🔧 AI Auto-Fix Engine – Starting"
echo "============================================"

# ── Read error log ────────────────────────────────────────────────────────────
ERROR_CONTENT=$(cat "${ERROR_FILE}" 2>/dev/null | head -c 6000 || echo "No errors found.")

# ── Collect relevant source files (top 5 most recently modified code files) ───
echo "📂 Collecting source files for context..."
SOURCE_CONTEXT=""
while IFS= read -r FILE; do
    RELATIVE=$(echo "${FILE}" | sed "s|${WORKSPACE}/||")
    CONTENT=$(cat "${FILE}" 2>/dev/null | head -c 1500)
    SOURCE_CONTEXT+="
--- FILE: ${RELATIVE} ---
${CONTENT}
"
done < <(find "${WORKSPACE}" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.java" -o -name "*.tf" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) \
         ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/vendor/*" \
         -newer "${ERROR_FILE}" 2>/dev/null | head -5)

# ── Build the fix prompt ──────────────────────────────────────────────────────
PROMPT="You are a senior DevSecOps engineer and code security expert. \
A Jenkins DevSecOps pipeline has detected the following security/code errors:\n\n\
ERRORS:\n${ERROR_CONTENT}\n\n\
RELEVANT SOURCE FILES:\n${SOURCE_CONTEXT}\n\n\
Your task is to FIX ALL the issues. For EACH fix:\n\
1. State clearly: FILENAME, WHAT was changed, and WHY.\n\
2. Provide the COMPLETE corrected file content in a code block like:\n\
   <<<FIX_FILE: path/to/file.ext>>>\n\
   <corrected full file content here>\n\
   <<<END_FIX>>>\n\
3. If the fix is a config change (e.g., .gitignore, .env.example), provide that too.\n\
4. At the end, write a SUMMARY section starting with ===SUMMARY=== listing all files changed.\n\
Focus on security fixes: remove hardcoded secrets, fix vulnerabilities, \
fix IaC misconfigurations. Only fix what is necessary — do not refactor unrelated code."

# ── Call Gemini API ───────────────────────────────────────────────────────────
echo "🤖 Calling Gemini API for fix generation..."

ESCAPED_PROMPT=$(printf '%s' "${PROMPT}" | python3 -c "
import sys, json
print(json.dumps(sys.stdin.read()))
" 2>/dev/null || echo "\"${PROMPT}\"")

REQUEST_BODY=$(cat <<EOF
{
  "contents": [{"parts": [{"text": ${ESCAPED_PROMPT}}]}],
  "generationConfig": {"temperature": 0.2, "maxOutputTokens": 4096}
}
EOF
)

HTTP_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    -X POST "${GEMINI_URL}" \
    -H "Content-Type: application/json" \
    -d "${REQUEST_BODY}")

HTTP_BODY=$(echo "${HTTP_RESPONSE}" | sed -e 's/HTTP_STATUS:.*//')
HTTP_STATUS=$(echo "${HTTP_RESPONSE}" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')

echo "Gemini API status: ${HTTP_STATUS}"

if [ "${HTTP_STATUS}" != "200" ]; then
    echo "❌ Gemini API failed: ${HTTP_STATUS}"
    echo "AI fix could not be applied. Manual intervention required." > "${FIX_SUMMARY}"
    exit 1
fi

# ── Parse Gemini response ─────────────────────────────────────────────────────
AI_RESPONSE=$(echo "${HTTP_BODY}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['candidates'][0]['content']['parts'][0]['text'])
except Exception as e:
    print(f'Parse error: {e}')
")

echo "✅ Gemini fix received. Applying patches..."

# ── Apply fixes: look for <<<FIX_FILE: ...>>> blocks and write them ───────────
echo "${AI_RESPONSE}" | python3 - "${WORKSPACE}" <<'PYEOF'
import sys, re, os

workspace = sys.argv[1]
content = sys.stdin.read()

# Find all fix blocks
pattern = r'<<<FIX_FILE:\s*(.+?)>>>\n(.*?)<<<END_FIX>>>'
matches = re.findall(pattern, content, re.DOTALL)

if not matches:
    print("ℹ️  No structured fix blocks found – AI may have used a different format.")
    print("Check ai_report.txt for manual fix instructions.")
else:
    for filepath, file_content in matches:
        filepath = filepath.strip()
        full_path = os.path.join(workspace, filepath)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        with open(full_path, 'w') as f:
            f.write(file_content.strip())
        print(f"✅ Fixed and wrote: {filepath}")
PYEOF

# ── Extract summary section ───────────────────────────────────────────────────
SUMMARY=$(echo "${AI_RESPONSE}" | awk '/===SUMMARY===/,0' | head -50)

{
    echo "============================================"
    echo "   🔧 AI AUTO-FIX SUMMARY"
    echo "   Applied at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================"
    echo ""
    if [ -n "${SUMMARY}" ]; then
        echo "${SUMMARY}"
    else
        echo "${AI_RESPONSE}" | tail -30
    fi
    echo ""
    echo "============================================"
} > "${FIX_SUMMARY}"

echo "✅ Fix summary written to ${FIX_SUMMARY}"
echo "🎉 AI auto-fix complete."
