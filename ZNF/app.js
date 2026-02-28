const express = require('express');
const app = express();

// VULNERABILITY 1: Hardcoded Secret! TruffleHog should catch this.
const GITHUB_TOKEN = "ghp_ThisIsAFakeGitHubTokenForTesting12345";

app.get('/student', function(req, res) {
    // VULNERABILITY 2: SQL Injection! SonarQube will flag this as critical.
    let studentId = req.query.id;
    let query = "SELECT * FROM students WHERE id = '" + studentId + "'";
    
    res.send("Executing Database Query: " + query);
});
