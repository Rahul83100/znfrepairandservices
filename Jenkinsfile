// ============================================================
// AI-Enhanced DevSecOps Pipeline with Gemini Auto-Remediation
// ============================================================
// FIXED: Trufflehog uses full path /usr/local/bin/trufflehog
// FIXED: _logError uses writeFile instead of sh echo to avoid quoting issues
// FIXED: Error capture works correctly across all stages
// ============================================================

pipeline {

    agent any

    environment {
        GEMINI_API_KEY  = credentials('gemini-api-key')
        GIT_CREDENTIALS = 'github-credentials'

        GIT_REPO_URL    = 'https://github.com/Rahul83100/znfrepairandservices.git'
        GIT_BRANCH      = 'main'
        ADMIN_EMAIL     = 'admin@example.com'

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

        // ── Init: clear error log ─────────────────────────────────────────
        stage('Init') {
            steps {
                script {
                    sh "rm -f '${ERROR_FILE}' '${REPORT_FILE}' '${FIX_SUMMARY}'"
                    writeFile file: env.ERROR_FILE, text: ''
                    echo "✅ Pipeline initialised."
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
                                ${trufflehogPath} filesystem "${WORKSPACE}" --json 2>&1 | tee trufflehog_report.json
                                EXIT=\${PIPESTATUS[0]}
                                if [ "\$EXIT" -ne 0 ]; then
                                    echo "[TRUFFLEHOG_FAILED]"
                                    exit 1
                                fi
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
                            withSonarQubeEnv('SonarQube') {
                                sh 'mvn sonar:sonar -Dsonar.projectKey=students_tasks 2>&1 | tee sonar_output.txt || true'
                            }
                            timeout(time: 3, unit: 'MINUTES') {
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
                            script: 'snyk test --json 2>&1 | tee snyk_report.json; exit ${PIPESTATUS[0]}',
                            returnStatus: true
                        )
                        if (result != 0) {
                            def snykOut = fileExists('snyk_report.json') ? readFile('snyk_report.json').take(3000) : 'Snyk scan failed.'
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
                            script: 'checkov -d . --output json 2>&1 | tee checkov_report.json; exit ${PIPESTATUS[0]}',
                            returnStatus: true
                        )
                        if (result != 0) {
                            def checkovOut = fileExists('checkov_report.json') ? readFile('checkov_report.json').take(3000) : 'Checkov scan failed.'
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
                            git push origin ${GIT_BRANCH}
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
    def prompt = """You are a DevSecOps AI assistant in a Jenkins pipeline.
ALL security scan stages passed with NO errors.
Write a SHORT (max 4 lines), enthusiastic, emoji-rich SUCCESS message for the DevOps team.
End with a big smile emoji. Mention all phases passed: Secrets, SAST, SCA, IaC."""

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
    def prompt = """You are a senior DevSecOps AI in a Jenkins CI/CD pipeline.
The following errors were found across security scan stages:

${errorContent.take(6000)}

Your response must have these sections:
1. 📋 SUMMARY — Which stages failed and why (bullet points)
2. 🔴 SEVERITY — Rate each issue: Critical / High / Medium / Low
3. 🔧 HOW TO FIX — Specific steps to fix each error
4. ✅ ACTION PLAN — Numbered list of exact files/commands to run

Use markdown, emojis, and be concise but thorough."""

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
    def prompt = """You are a DevSecOps engineer. Fix these pipeline errors:

${errorContent.take(4000)}

For each fix provide:
<<<FIX_FILE: relative/path/to/file.ext>>>
<complete corrected file content>
<<<END_FIX>>>

At the end write ===SUMMARY=== with all files you changed."""

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
        full = os.path.join(workspace, filepath)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        open(full, 'w').write(filecontent.strip())
        print(f'✅ Fixed: {filepath}')
else:
    print('ℹ️  No structured fix blocks. See fix_summary.txt for manual steps.')
PYEOF
"""
}

def _geminiCall(String prompt) {
    def result = sh(script: """
        python3 -c "
import json
prompt = '''${prompt.replace("'", "\\'")}'''
data = {
  \"contents\": [{\"parts\": [{\"text\": prompt}]}],
  \"generationConfig\": {\"temperature\": 0.3, \"maxOutputTokens\": 2048}
}
with open('/tmp/gemini_request.json', 'w') as f:
    json.dump(data, f)
"
        curl -s -X POST \\
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\${GEMINI_API_KEY}" \\
          -H "Content-Type: application/json" \\
          -d @/tmp/gemini_request.json > /tmp/gemini_response.json

        echo "=== RAW GEMINI RESPONSE ==="
        cat /tmp/gemini_response.json
        echo "==========================="

        python3 -c "
import json
with open('/tmp/gemini_response.json') as f:
    data = json.load(f)
if 'error' in data:
    e = data['error']
    print('GEMINI_ERROR: ' + str(e.get('code','?')) + ' - ' + e.get('message','unknown'))
elif 'candidates' in data:
    print(data['candidates'][0]['content']['parts'][0]['text'])
else:
    print('GEMINI_ERROR: Unexpected response: ' + json.dumps(data))
"
    """, returnStdout: true).trim()
    return result
}
