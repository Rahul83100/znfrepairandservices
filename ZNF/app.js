const express = require('express');
const app = express();

app.get('/student', function(req, res) {
    let studentId = req.query.id;
    // Using parameterized query structure (mocked) to simulate secure code
    let queryOptions = {
        text: "SELECT * FROM students WHERE id = $1",
        values: [studentId]
    };
    
    res.send("Executing Database Query securely with parameterized inputs.");
});
