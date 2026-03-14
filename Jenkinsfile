// ============================================================
// AI-Enhanced DevSecOps Pipeline with Gemini Auto-Remediation
// ============================================================
// Stages:        Checkout → Secrets Scan → SAST → SCA → IaC → AI Review
// Error policy:  Every stage uses catchError so the pipeline ALWAYS
//                continues to Phase 4 even if earlier stages fail.
// Phase 4 flow:
//   - Errors found → Gemini report → Admin: Approve/Decline
//       Approve  → AI fixes code → git commit + push → new build → notify
//       Decline  → mark FAILED
//   - No errors  → Gemini prints success message → Build SUCCESS
// ============================================================

pipeline {

    agent any

    // ── Environment / Credentials ────────────────────────────────────────
    environment {
        // Jenkins Credentials (add via Manage Jenkins → Credentials)
      GEMINI_API_KEY  = credentials('gemini-api-key')
GIT_CREDENTIALS = 'github-credentials'    // Username+Password
          

        // Repo details – update these to match your project
        GIT_REPO_URL    = 'https://github.com/YOUR_ORG/YOUR_REPO.git'
        GIT_BRANCH      = 'main'

        // Notification
        ADMIN_EMAIL     = 'admin@example.com'

        // Workspace artefacts
        ERROR_FILE      = "${WORKSPACE}/scan_errors.txt"
        REPORT_FILE     = "${WORKSPACE}/ai_report.txt"
        FIX_SUMMARY     = "${WORKSPACE}/fix_summary.txt"

        // Pipeline-level error flag (updated inside stages)
        PIPELINE_HAS_ERRORS = 'false'
    }

    options {
        timestamps()
        ansiColor('xterm')
        timeout(time: 60, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    stages {

        // ── Stage 0: Initialise error log ────────────────────────────────
        stage('Init') {
            steps {
                script {
                    sh "rm -f '${ERROR_FILE}' '${REPORT_FILE}' '${FIX_SUMMARY}'"
                    sh "touch '${ERROR_FILE}'"
                    echo "✅ Pipeline initialised – error log cleared."
                }
            }
        }

        // ── Stage 1: Checkout ────────────────────────────────────────────
        stage('Checkout Source Code') {
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                    checkout scm
                    echo "✅ Source code checked out."
                }
            }
            post {
                failure {
                    script { _logError('Checkout Source Code', 'Failed to checkout source code from SCM.') }
                }
            }
        }

        // ── Stage 2a: Secrets Scanning (Trufflehog) ──────────────────────
        stage('Phase 2: Secrets Scanning (Trufflehog)') {
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                    sh '''
                        set +e
                        echo "🔍 Running Trufflehog secrets scan..."
                        SCAN_OUTPUT=$(trufflehog filesystem . --json 2>&1)
                        EXIT_CODE=$?
                        if [ $EXIT_CODE -ne 0 ] || echo "$SCAN_OUTPUT" | grep -q '"verified":true'; then
                            echo "[ERROR] Trufflehog found secrets or failed to scan."
                            echo "$SCAN_OUTPUT"
                            exit 1
                        fi
                        echo "✅ No secrets detected."
                    '''
                }
            }
            post {
                failure {
                    script {
                        def out = sh(script: "trufflehog filesystem . --json 2>&1 || true", returnStdout: true).trim()
                        _logError('Secrets Scanning (Trufflehog)', out ?: 'Trufflehog scan failed or found secrets.')
                    }
                }
            }
        }

        // ── Stage 2b: SAST (SonarQube) ───────────────────────────────────
        stage('Phase 2: SAST (SonarQube)') {
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                    withSonarQubeEnv('SonarQube') {
                        sh 'mvn sonar:sonar -Dsonar.projectKey=students_tasks || true'
                    }
                    timeout(time: 5, unit: 'MINUTES') {
                        script {
                            def qg = waitForQualityGate()
                            if (qg.status != 'OK') {
                                error("SonarQube Quality Gate failed: ${qg.status}")
                            }
                        }
                    }
                }
            }
            post {
                failure {
                    script { _logError('SAST (SonarQube)', 'SonarQube quality gate failed. Check SonarQube dashboard for issues.') }
                }
            }
        }

        // ── Stage 2c: SCA (Snyk) ─────────────────────────────────────────
        stage('Phase 2: SCA (Snyk)') {
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                    sh '''
                        set +e
                        echo "🔍 Running Snyk dependency scan..."
                        snyk test --json > snyk_report.json 2>&1
                        EXIT_CODE=$?
                        cat snyk_report.json
                        if [ $EXIT_CODE -ne 0 ]; then
                            echo "[ERROR] Snyk found vulnerabilities."
                            exit 1
                        fi
                        echo "✅ No Snyk vulnerabilities found."
                    '''
                }
            }
            post {
                failure {
                    script {
                        def snykOut = fileExists('snyk_report.json') ? readFile('snyk_report.json') : 'Snyk scan failed.'
                        _logError('SCA (Snyk)', snykOut.take(2000))
                    }
                }
            }
        }

        // ── Stage 3: IaC Scanning (Checkov) ──────────────────────────────
        stage('Phase 3: IaC Scanning (Checkov)') {
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
                    sh '''
                        set +e
                        echo "🔍 Running Checkov IaC scan..."
                        checkov -d . --output json > checkov_report.json 2>&1
                        EXIT_CODE=$?
                        cat checkov_report.json
                        if [ $EXIT_CODE -ne 0 ]; then
                            echo "[ERROR] Checkov found IaC misconfigurations."
                            exit 1
                        fi
                        echo "✅ No IaC issues found."
                    '''
                }
            }
            post {
                failure {
                    script {
                        def checkovOut = fileExists('checkov_report.json') ? readFile('checkov_report.json') : 'Checkov scan failed.'
                        _logError('IaC Scanning (Checkov)', checkovOut.take(2000))
                    }
                }
            }
        }

        // ── Stage 4: AI Assessment & Remediation (Gemini) ────────────────
        stage('Phase 4: AI Assessment & Remediation (Gemini)') {
            steps {
                script {

                    // ── 4a: Check if any errors were logged ───────────────
                    def errorContent = readFile(ERROR_FILE).trim()
                    boolean hasErrors = errorContent.length() > 0

                    if (!hasErrors) {
                        // ── No-error path ─────────────────────────────────
                        echo "🤖 Gemini AI Analysis: Calling Gemini API..."
                        sh """
                            bash '${WORKSPACE}/scripts/ai_analyze.sh' \
                                '${GEMINI_API_KEY}' \
                                '${ERROR_FILE}'     \
                                '${REPORT_FILE}'    \
                                'no_errors'
                        """
                        echo "============================================"
                        echo "✅  ALL STAGES PASSED – NO ERRORS DETECTED"
                        echo "============================================"
                        sh "cat '${REPORT_FILE}'"
                        currentBuild.result = 'SUCCESS'
                        return
                    }

                    // ── 4b: Errors exist – generate AI report ─────────────
                    echo "⚠️  Errors detected in one or more stages. Calling Gemini AI..."
                    sh """
                        bash '${WORKSPACE}/scripts/ai_analyze.sh' \
                            '${GEMINI_API_KEY}' \
                            '${ERROR_FILE}'     \
                            '${REPORT_FILE}'    \
                            'with_errors'
                    """

                    echo "============================================"
                    echo "         🤖 GEMINI AI ERROR REPORT"
                    echo "============================================"
                    sh "cat '${REPORT_FILE}'"
                    echo "============================================"

                    // Archive report as build artifact
                    archiveArtifacts artifacts: 'ai_report.txt', allowEmptyArchive: true

                    // ── 4c: Admin Approve / Decline ───────────────────────
                    def userInput
                    timeout(time: 30, unit: 'MINUTES') {
                        userInput = input(
                            id: 'aiFixApproval',
                            message: '🤖 AI has identified errors (see report above). Approve AI auto-fix?',
                            submitterParameter: 'APPROVER',
                            parameters: [
                                choice(
                                    name: 'ACTION',
                                    choices: ['Approve', 'Decline'],
                                    description: '✅ Approve = AI will fix all errors, commit & push.\n❌ Decline = Mark build as FAILED.'
                                )
                            ]
                        )
                    }

                    if (userInput.ACTION == 'Decline') {
                        currentBuild.result = 'FAILURE'
                        error("❌ Admin declined AI auto-fix. Build marked as FAILED.")
                    }

                    // ── 4d: Apply AI fix ──────────────────────────────────
                    echo "✅ Admin approved. Applying AI-generated fixes..."
                    sh """
                        bash '${WORKSPACE}/scripts/apply_fix.sh' \
                            '${GEMINI_API_KEY}' \
                            '${ERROR_FILE}'     \
                            '${WORKSPACE}'      \
                            '${FIX_SUMMARY}'
                    """
                    echo "============================================"
                    echo "         🔧 FIX SUMMARY"
                    echo "============================================"
                    sh "cat '${FIX_SUMMARY}'"

                    // ── 4e: Git commit & push ─────────────────────────────
                    withCredentials([usernamePassword(
                        credentialsId: GIT_CREDENTIALS,
                        usernameVariable: 'GIT_USER',
                        passwordVariable: 'GIT_PASS'
                    )]) {
                        sh """
                            git config user.email "jenkins-ai@pipeline.local"
                            git config user.name  "Jenkins AI Bot"
                            git add -A
                            git diff --cached --quiet || git commit -m "🤖 AI Auto-Fix: resolved errors from build #${BUILD_NUMBER}"
                            git remote set-url origin https://\${GIT_USER}:\${GIT_PASS}@\$(echo '${GIT_REPO_URL}' | sed 's|https://||')
                            git push origin ${GIT_BRANCH}
                        """
                    }
                    echo "✅ Changes committed and pushed to ${GIT_BRANCH}."

                    // ── 4f: Notify admins ─────────────────────────────────
                    sh """
                        bash '${WORKSPACE}/scripts/notify_admin.sh' \
                            '${ADMIN_EMAIL}'   \
                            '${BUILD_NUMBER}'  \
                            '${FIX_SUMMARY}'   \
                            '${env.BUILD_URL ?: "N/A"}'
                    """

                    // ── 4g: Trigger new build ─────────────────────────────
                    echo "🚀 Triggering new pipeline run to verify fix..."
                    build job: env.JOB_NAME, wait: false, propagate: false

                    echo "============================================"
                    echo "   🎉 ERROR FIXED – New build triggered!"
                    echo "============================================"
                }
            }
        }

    } // end stages

    // ── Global Post Actions ───────────────────────────────────────────────
    post {
    always {
        script {
            try {
                archiveArtifacts artifacts: 'scan_errors.txt, ai_report.txt, fix_summary.txt, snyk_report.json, checkov_report.json', allowEmptyArchive: true
            } catch (err) {
                echo "Artifact archiving skipped: ${err.message}"
            }
        }
    }

        success {
            echo "🎉 Pipeline completed successfully!"
        }
        unstable {
            echo "⚠️  Pipeline completed with warnings. Check Phase 4 AI report."
        }
        failure {
            echo "❌ Pipeline FAILED. Check the AI report and stage logs above."
        }
    }

} // end pipeline

// ── Helper: append error to the shared error log ─────────────────────────────
def _logError(String stageName, String message) {
    def timestamp = new Date().format("yyyy-MM-dd HH:mm:ss")
    def entry = """
====== ERROR IN: ${stageName} [${timestamp}] ======
${message}
=================================================
"""
    sh "echo '${entry.replace("'", "'\\''").trim()}' >> '${WORKSPACE}/scan_errors.txt'"
    env.PIPELINE_HAS_ERRORS = 'true'
    echo "⚠️  Error logged from stage: ${stageName}"
}
