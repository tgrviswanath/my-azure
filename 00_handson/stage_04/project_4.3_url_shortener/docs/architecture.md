# Architecture — Project 4.3 URL Shortener

## Flow

```
POST /api/shorten {"url":"..."}
  → Function generates 6-char code
  → Stores {id: code, original_url, clicks} in Cosmos DB
  → Returns short URL

GET /api/r/{code}
  → Function reads Cosmos DB
  → Increments click counter
  → Returns HTTP 302 redirect to original URL
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| HTTP 302 | Temporary redirect — browser follows Location header |
| Partition key `/id` | Short code is both ID and partition key |
| Click analytics | Cosmos DB change feed can stream click events |
| Collision handling | Retry with new code if code already exists |
