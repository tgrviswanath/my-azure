# Project 4.3 — URL Shortener

## What This Does
Serverless URL shortener: API Management → Azure Function → Cosmos DB.

## How to Run
```bash
# Shorten a URL
curl -X POST https://<func>.azurewebsites.net/api/shorten \
  -d '{"url":"https://example.com/very/long/url"}'
# Returns: {"short_code":"abc123","short_url":"https://<func>.azurewebsites.net/api/r/abc123"}

# Redirect
curl -L https://<func>.azurewebsites.net/api/r/abc123
```

## Lessons Learned
- Use nanoid/uuid for short codes — avoid sequential IDs (guessable)
- Cache popular redirects in memory or Redis for performance
- Store click analytics in Cosmos DB change feed
