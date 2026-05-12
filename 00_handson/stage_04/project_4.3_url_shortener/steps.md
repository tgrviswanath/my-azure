# Steps — Project 4.3 URL Shortener

## Phase 1 — Deploy
```bash
cd terraform && terraform init && terraform apply -auto-approve
func azure functionapp publish func-url-shortener-001
```

## Phase 2 — Test
```bash
BASE=https://func-url-shortener-001.azurewebsites.net/api

# Shorten
curl -X POST $BASE/shorten -H "Content-Type: application/json" \
  -d '{"url":"https://docs.microsoft.com/en-us/azure/functions/functions-overview"}'

# Redirect (follow redirect)
curl -L $BASE/r/<code>
```

## Screenshots to Take
- [ ] Short URL created
- [ ] Redirect working
- [ ] Click count incrementing in Cosmos DB
