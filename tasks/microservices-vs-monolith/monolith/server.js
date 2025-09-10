const express = require("express");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;

// Serve frontend
app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "index.html"));
});

// API endpoint
app.get("/api/hello", (req, res) => {
  res.json({ message: "Hello from Monolith API 🚀" });
});

app.listen(PORT, () => {
  console.log(`Monolith app running on port ${PORT}`);
});
