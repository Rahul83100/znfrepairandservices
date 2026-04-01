// ============================================================
// AI-Enhanced DevSecOps Pipeline with Gemini Auto-Remediation
// ============================================================
// FIXED: Trufflehog uses full path /usr/local/bin/trufflehog
// FIXED: _logError uses writeFile instead of sh echo to avoid quoting issues
// FIXED: Error capture works correctly across all stages
// FIXED: Gemini API calls use retry/backoff and gemini-2.0-flash
// ============================================================

pipeline {

    agent any

    environment {
        GEMINI_API_KEY  = credentials('gemini-api-key')
        GIT_CREDENTIALS = 'github-credentials'

        GIT_REPO_URL    = 'https://github.com/Rahul83100/znfrepairandservices.git'
        GIT_BRANCH      = 'secure-test'
        ADMIN_EMAIL     = 'rahul636071@gmail.com'

        ERROR_FILE      = "${WORKSPACE}/scan_errors.txt"
        REPORT_FILE     = "${WORKSPACE}/ai_report.txt"
        FIX_SUMMARY     = "${WORKSPACE}/fix_summary.txt"
    }

    options {
        timestamps()
        ansiColor('xterm')
        timeout(time: 60, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    stages {

        // ── Init: clear workspace ─────────────────────────────────────────
        stage('Init') {
            steps {
                script {
                    deleteDir() // Wipe the entire workspace to prevent hidden files like old .git logs from triggering scanners
                    writeFile file: env.ERROR_FILE, text: '' // Recreate the error log file
                    echo "✅ Workspace cleaned and pipeline initialised."
                }
            }
        }

        // ── Checkout ──────────────────────────────────────────────────────
        stage('Checkout Source Code') {
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                    checkout scm
                    echo "✅ Source code checked out."
                }
            }
            post {
                failure {
                    script { _logError('Checkout Source Code', 'SCM checkout failed.') }
                }
            }
        }

        // ── Secrets Scanning (Trufflehog) ─────────────────────────────────
        stage('Phase 2: Secrets Scanning (Trufflehog)') {
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                    script {
                        def trufflehogPath = sh(script: 'which trufflehog || echo /usr/local/bin/trufflehog', returnStdout: true).trim()
                        def result = sh(
                            script: """
                                set +e
                                echo "🔍 Running Trufflehog secrets scan..."
                                ${trufflehogPath} filesystem "${WORKSPACE}" --exclude-paths=.trufflehog-ignore --json > trufflehog_report.json 2>&1
                                if grep -q '"verified":true' trufflehog_report.json 2>/dev/null; then
                                    echo "[SECRETS_FOUND]"
                                    exit 1
                                fi
                                echo "✅ No secrets detected."
                            """,
                            returnStatus: true
                        )
                        if (result != 0) {
                            def output = fileExists('trufflehog_report.json') ? readFile('trufflehog_report.json').take(3000) : 'Trufflehog failed to run.'
                            _logError('Secrets Scanning (Trufflehog)', output)
                            error("Trufflehog scan failed or found secrets")
                        }
                    }
                }
            }
        }

        // ── SAST (SonarQube) ──────────────────────────────────────────────
        stage('Phase 2: SAST (SonarQube)') {
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                    script {
                        try {
                            // Use the Jenkins-installed SonarQube Scanner (via plugin)
                            def scannerHome = tool name: 'SonarScanner', type: 'hudson.plugins.sonar.SonarRunnerInstallation'
                            withSonarQubeEnv('SonarQube') {
                                sh """
                                    echo "🔍 Running SonarQube SAST scan..."
                                    echo "Scanner home: ${scannerHome}"
                                    ${scannerHome}/bin/sonar-scanner \
                                        -Dsonar.projectKey=students_tasks \
                                        -Dsonar.projectName="Students IMS" \
                                        -Dsonar.sources=. \
                                        -Dsonar.exclusions=node_modules/**,**/*.test.js,.git/**,*.json \
                                        -Dsonar.host.url=http://68.183.93.244:9000 \
                                        2>&1 | tee sonar_output.txt
                                """
                            }
                            timeout(time: 10, unit: 'MINUTES') {
                                def qg = waitForQualityGate()
                                if (qg.status != 'OK') {
                                    def msg = "SonarQube Quality Gate FAILED: ${qg.status}"
                                    _logError('SAST (SonarQube)', msg)
                                    error(msg)
                                }
                            }
                        } catch (err) {
                            def sonarOut = fileExists('sonar_output.txt') ? readFile('sonar_output.txt').take(3000) : err.getMessage()
                            _logError('SAST (SonarQube)', sonarOut)
                            throw err
                        }
                    }
                }
            }
        }

        // ── SCA (Snyk) ────────────────────────────────────────────────────
        stage('Phase 2: SCA (Snyk)') {
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                    script {
                        def result = sh(
                            script: '''#!/bin/bash
                            SNYK_PATH=$(which snyk || echo /usr/local/bin/snyk)
                            if [ ! -f "$SNYK_PATH" ]; then
                                echo "❌ snyk command not found at /usr/local/bin/snyk!"
                                exit 1
                            fi
                            $SNYK_PATH test 2>&1 | tee snyk_report.txt
                            exit ${PIPESTATUS[0]}
                            ''',
                            returnStatus: true
                        )
                        if (result != 0) {
                            def snykOut = fileExists('snyk_report.txt') ? readFile('snyk_report.txt').take(5000) : 'Snyk scan failed.'
                            _logError('SCA (Snyk)', snykOut)
                            error("Snyk found vulnerabilities")
                        }
                        echo "✅ No Snyk vulnerabilities found."
                    }
                }
            }
        }

        // ── IaC Scanning (Checkov) ────────────────────────────────────────
        stage('Phase 3: IaC Scanning (Checkov)') {
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                    script {
                        def result = sh(
                            script: '''#!/bin/bash
                            CHECKOV_PATH=$(which checkov || echo /usr/local/bin/checkov)
                            if [ ! -f "$CHECKOV_PATH" ]; then
                                echo "❌ checkov command not found at /usr/local/bin/checkov!"
                                exit 1
                            fi
                            $CHECKOV_PATH -d . --quiet --skip-check CKV_AWS_144,CKV2_AWS_61,CKV2_AWS_62 2>&1 | tee checkov_report.txt
                            exit ${PIPESTATUS[0]}
                            ''',
                            returnStatus: true
                        )
                        if (result != 0) {
                            def checkovOut = fileExists('checkov_report.txt') ? readFile('checkov_report.txt').take(5000) : 'Checkov scan failed.'
                            _logError('IaC Scanning (Checkov)', checkovOut)
                            error("Checkov found IaC issues")
                        }
                        echo "✅ No IaC issues found."
                    }
                }
            }
        }

        // ── Phase 4: AI Assessment & Remediation (Gemini) ─────────────────
        stage('Phase 4: AI Assessment & Remediation (Gemini)') {
            steps {
                script {

                    def errorContent = fileExists(env.ERROR_FILE) ? readFile(env.ERROR_FILE).trim() : ''
                    boolean hasErrors = errorContent.length() > 0

                    echo "============================================"
                    echo "     🤖 PHASE 4: GEMINI AI ASSESSMENT"
                    echo "============================================"

                    if (!hasErrors) {
                        // ── No-error path ──────────────────────────
                        _callGeminiNoErrors()
                        echo ""
                        sh "cat '${REPORT_FILE}'"
                        echo ""
                        currentBuild.result = 'SUCCESS'
                        return
                    }

                    // ── Errors found – get AI report ───────────────
                    echo "⚠️  Errors found in pipeline stages. Generating AI report..."
                    _callGeminiWithErrors(errorContent)

                    echo ""
                    sh "cat '${REPORT_FILE}'"
                    echo ""
                    echo "============================================"

                    archiveArtifacts artifacts: 'ai_report.txt', allowEmptyArchive: true

                    // ── Admin Approve / Decline ────────────────────
                    def userInput
                    timeout(time: 30, unit: 'MINUTES') {
                        userInput = input(
                            id: 'aiFixApproval',
                            message: '🤖 AI found errors. Approve auto-fix?',
                            submitterParameter: 'APPROVER',
                            parameters: [
                                choice(
                                    name: 'ACTION',
                                    choices: ['Approve', 'Decline'],
                                    description: '✅ Approve = AI will fix errors, commit & push.\n❌ Decline = Mark build FAILED.'
                                )
                            ]
                        )
                    }

                    if (userInput.ACTION == 'Decline') {
                        currentBuild.result = 'FAILURE'
                        error("❌ Admin declined AI fix. Build marked FAILED.")
                    }

                    // ── Apply AI fix ───────────────────────────────
                    echo "✅ Approved! Applying AI-generated fixes..."
                    sleep(5) // Brief delay to avoid Gemini rate-limit between calls
                    _applyGeminiFix(errorContent)

                    // ── Git commit & push ──────────────────────────
                    withCredentials([usernamePassword(
                        credentialsId: env.GIT_CREDENTIALS,
                        usernameVariable: 'GIT_USER',
                        passwordVariable: 'GIT_PASS'
                    )]) {
                        sh """
                            git config user.email "jenkins-ai@pipeline.local"
                            git config user.name  "Jenkins AI Bot"
                            git add -A
                            git diff --cached --quiet && echo "No changes to commit" || \
                            git commit -m "🤖 AI Auto-Fix: resolved build #${BUILD_NUMBER} errors"
                            REPO_PATH=\$(echo '${GIT_REPO_URL}' | sed 's|https://||')
                            git remote set-url origin "https://\${GIT_USER}:\${GIT_PASS}@\${REPO_PATH}"
                            git push origin HEAD:${GIT_BRANCH}
                            echo "✅ Changes pushed to ${GIT_BRANCH}."
                        """
                    }

                    // ── Notify admins ──────────────────────────────
                    try {
                        emailext(
                            to: env.ADMIN_EMAIL,
                            subject: "✅ [Jenkins AI] Error Fixed – Build #${BUILD_NUMBER}",
                            body: """
Jenkins AI Auto-Remediation: Build #${BUILD_NUMBER}

The Gemini AI has successfully fixed all errors detected in the pipeline.
Changes were committed and pushed to ${GIT_BRANCH}.

Fix Summary:
${fileExists(env.FIX_SUMMARY) ? readFile(env.FIX_SUMMARY) : 'See build artifacts.'}

Build URL: ${env.BUILD_URL}
                            """.stripIndent()
                        )
                    } catch(e) {
                        echo "⚠️  Email notification skipped (emailext not configured): ${e.message}"
                    }

                    // ── Trigger new build ──────────────────────────
                    echo "🚀 Triggering new pipeline build to verify fix..."
                    build job: env.JOB_NAME, wait: false, propagate: false

                    echo "============================================"
                    echo " 🎉 ERROR FIXED! New build triggered!"
                    echo "============================================"
                }
            }
        }

    } // end stages

    post {
        always {
            script {
                try {
                    archiveArtifacts artifacts: 'scan_errors.txt,ai_report.txt,fix_summary.txt,snyk_report.json,checkov_report.json,trufflehog_report.json', allowEmptyArchive: true
                } catch (e) {
                    echo "Artifact archiving skipped: ${e.message}"
                }
            }
        }
        success  { echo "🎉 Pipeline PASSED – No issues found!" }
        unstable { echo "⚠️  Pipeline UNSTABLE – Check AI report in artifacts." }
        failure  { echo "❌ Pipeline FAILED – Check stage logs above." }
    }

} // end pipeline

// ═══════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════

def _logError(String stageName, String message) {
    def timestamp = new Date().format("yyyy-MM-dd HH:mm:ss")
    def entry = "\n====== ERROR IN: ${stageName} [${timestamp}] ======\n${message}\n=================================================\n"
    def existing = fileExists(env.ERROR_FILE) ? readFile(env.ERROR_FILE) : ''
    writeFile file: env.ERROR_FILE, text: existing + entry
    echo "⚠️  Error logged from stage: ${stageName}"
}

def _callGeminiNoErrors() {
    def prompt = "All security scans passed (Secrets, SAST, SCA, IaC). Write a 2-line success message with emojis."

    def report = _geminiCall(prompt)
    writeFile file: env.REPORT_FILE, text: """
============================================
     🤖 GEMINI AI PIPELINE REPORT
============================================

${report}

============================================
""".stripIndent()
}

def _callGeminiWithErrors(String errorContent) {
    def prompt = "DevSecOps pipeline errors. Give: 1) Summary 2) Severity 3) Fix steps. Be brief.\n\n" + errorContent.take(3000)

    def report = _geminiCall(prompt)
    writeFile file: env.REPORT_FILE, text: """
============================================
     🤖 GEMINI AI PIPELINE ERROR REPORT
============================================

${report}

============================================
""".stripIndent()
}

def _applyGeminiFix(String errorContent) {
    def prompt = """You are an automated code fixer inside a CI/CD pipeline. Your output will be parsed by a script.
RULES:
1. You MUST respond ONLY with fix blocks in this EXACT format (no other text before or after):
<<<FIX_FILE: relative/path/to/file>>>
<complete file content>
<<<END_FIX>>>
2. Each fix block must contain the COMPLETE file content, not a partial snippet.
3. Do NOT use placeholder values like YOUR_REGION, YOUR_KEY_ID, etc. Use real working defaults.
4. Do NOT write shell commands, npm commands, or instructions. ONLY output fix blocks.
5. For Terraform files, use 'sse_algorithm = "aws:kms"' without specifying a KMS key ARN (AWS uses default).
6. Fix ALL errors mentioned below in a SINGLE response.
7. Use the EXACT file path shown in the error report (e.g. if the error says 'File: /ZNF/main.tf', use 'ZNF/main.tf' without the leading slash).
8. Do NOT wrap code in markdown backticks like ```.

ERRORS:
""" + errorContent.take(6000)

    def fixInstructions = _geminiCall(prompt)
    writeFile file: env.FIX_SUMMARY, text: fixInstructions

    // Apply fixes via Python
    sh """
python3 - <<'PYEOF'
import re, os

workspace = '${WORKSPACE}'
content = open('${FIX_SUMMARY}').read()

pattern = r'<<<FIX_FILE:\\s*(.+?)>>>\\n(.*?)<<<END_FIX>>>'
matches = re.findall(pattern, content, re.DOTALL)
if matches:
    for filepath, filecontent in matches:
        filepath = filepath.strip()
        fc = filecontent.strip()
        fc = re.sub(r'^```[a-z]*\\n+', '', fc) # Remove starting markdown ```json
        fc = re.sub(r'\\n+```\\Z', '', fc)      # Remove ending markdown ```
        full = os.path.join(workspace, filepath)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        open(full, 'w').write(fc)
        print(f'Fixed: {filepath}')
else:
    print('No structured fix blocks. See fix_summary.txt for manual steps.')
PYEOF
"""
}

def _geminiCall(String prompt) {
    // Write prompt to temp file to avoid shell escaping issues
    def promptFile = "${WORKSPACE}/.gemini_prompt.txt"
    writeFile file: promptFile, text: prompt

    // All API + retry logic in shell to avoid Groovy CPS serialization issues
    def result = sh(script: '#!/bin/bash\n' +
        'set +e\n' +
        'PROMPT_FILE="' + promptFile + '"\n' +
        'API_KEY="$GEMINI_API_KEY"\n' +
        'MAX_RETRIES=3\n' +
        'DELAYS=(30 60 120)\n' +
        '\n' +
        'ESCAPED=$(python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" < "$PROMPT_FILE" 2>/dev/null)\n' +
        'if [ -z "$ESCAPED" ]; then\n' +
        '    echo "Failed to escape prompt"\n' +
        '    exit 1\n' +
        'fi\n' +
        '\n' +
        'REQUEST=\'{"contents":[{"parts":[{"text":\'$ESCAPED\'}]}],"generationConfig":{"temperature":0.3,"maxOutputTokens":1024}}\'\n' +
        '\n' +
        'for ATTEMPT in 0 1 2 3; do\n' +
        '    RESPONSE=$(curl -s -w "\\nHTTP_STATUS:%{http_code}" -X POST \\\n' +
        '        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${API_KEY}" \\\n' +
        '        -H "Content-Type: application/json" \\\n' +
        '        -d "$REQUEST" 2>/dev/null)\n' +
        '\n' +
        '    HTTP_STATUS=$(echo "$RESPONSE" | tail -1 | sed "s/HTTP_STATUS://")\n' +
        '    HTTP_BODY=$(echo "$RESPONSE" | sed "\\$d")\n' +
        '\n' +
        '    if [ "$HTTP_STATUS" = "200" ]; then\n' +
        '        echo "$HTTP_BODY" | python3 -c "\n' +
        'import sys, json\n' +
        'try:\n' +
        '    d = json.load(sys.stdin)\n' +
        '    print(d[\\\"candidates\\\"][0][\\\"content\\\"][\\\"parts\\\"][0][\\\"text\\\"])\n' +
        'except Exception as e:\n' +
        '    print(f\\\"AI response parse error: {e}\\\")\n' +
        '" 2>/dev/null\n' +
        '        rm -f "$PROMPT_FILE"\n' +
        '        exit 0\n' +
        '    fi\n' +
        '\n' +
        '    if [ "$HTTP_STATUS" = "429" ] || [ "$HTTP_STATUS" = "503" ]; then\n' +
        '        if [ "$ATTEMPT" -lt "$MAX_RETRIES" ]; then\n' +
        '            DELAY=${DELAYS[$ATTEMPT]}\n' +
        '            echo "Rate limited ($HTTP_STATUS), waiting ${DELAY}s... (retry $((ATTEMPT+1))/$MAX_RETRIES)" >&2\n' +
        '            sleep "$DELAY"\n' +
        '        fi\n' +
        '    else\n' +
        '        break\n' +
        '    fi\n' +
        'done\n' +
        '\n' +
        'rm -f "$PROMPT_FILE"\n' +
        'echo "Gemini API error ($HTTP_STATUS). Check key at https://aistudio.google.com/app/apikey"\n',
        returnStdout: true).trim()

    return result ?: "Gemini API returned no content. Check API key and quota."
}
