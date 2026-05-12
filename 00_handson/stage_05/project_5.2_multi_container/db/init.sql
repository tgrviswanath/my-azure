CREATE TABLE IF NOT EXISTS items (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO items (name) VALUES ('Sample Item 1'), ('Sample Item 2');
