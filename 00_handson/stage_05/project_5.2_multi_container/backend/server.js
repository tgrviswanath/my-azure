const express = require("express");
const { Pool } = require("pg");
const redis = require("redis");

const app = express();
app.use(express.json());

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const redisClient = redis.createClient({ url: process.env.REDIS_URL });
redisClient.connect().catch(console.error);

app.get("/health", (req, res) => res.json({ status: "healthy" }));

app.get("/items", async (req, res) => {
  const cached = await redisClient.get("items");
  if (cached) return res.json({ source: "cache", data: JSON.parse(cached) });

  const result = await pool.query("SELECT * FROM items ORDER BY created_at DESC");
  await redisClient.setEx("items", 60, JSON.stringify(result.rows));
  res.json({ source: "db", data: result.rows });
});

app.post("/items", async (req, res) => {
  const { name } = req.body;
  const result = await pool.query(
    "INSERT INTO items (name) VALUES ($1) RETURNING *",
    [name]
  );
  await redisClient.del("items");
  res.status(201).json(result.rows[0]);
});

app.listen(4000, () => console.log("Backend running on :4000"));
