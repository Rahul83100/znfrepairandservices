import urllib.request
import json
import os

api_key = os.environ.get('GEMINI_API_KEY')
url = f'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={api_key}'

try:
    with open('snyk_report.txt', 'r') as f:
        report = f.read()[:3000] 
except Exception:
    report = "No Snyk report found."

prompt = f"""You are an expert DevSecOps AI. Read this Snyk vulnerability report: {report}
Write a bash script to fix the vulnerabilities in the code.
IMPORTANT: OUTPUT ONLY THE RAW BASH COMMANDS. Do not include markdown formatting, backticks, or explanations."""

data = {"contents": [{"parts": [{"text": prompt}]}]}
req = urllib.request.Request(url, data=json.dumps(data).encode('utf-8'), headers={'Content-Type': 'application/json'})

try:
    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read().decode('utf-8'))
        text = result['candidates'][0]['content']['parts'][0]['text']
        
        text = text.replace("```bash", "").replace("```", "").strip()
        
        with open('apply_fix.sh', 'w') as f:
            f.write(text)
except Exception as e:
    with open('apply_fix.sh', 'w') as f:
        f.write(f"echo 'Failed to contact Gemini API: {e}'")
