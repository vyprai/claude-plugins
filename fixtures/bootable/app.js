const express = require("express");
const fs = require("fs");
const app = express();

app.get("/download", (req, res) => {
  const name = req.query.name;
  res.send(fs.readFileSync("/var/data/" + name));
});

app.listen(3000, "0.0.0.0");
