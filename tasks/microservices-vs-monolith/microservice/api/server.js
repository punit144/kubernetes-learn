const express = require("express");
const app = express();
const PORT = process.env.PORT || 4000;

app.get("/hello", (req, res) => {
  res.json({ message: "Hello from Microservice API 🎯" });
});

app.listen(PORT, () => {
  console.log(`API running on port ${PORT}`);
});
