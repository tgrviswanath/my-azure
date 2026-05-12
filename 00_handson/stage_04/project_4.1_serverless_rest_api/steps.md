# Steps — Project 4.1 Serverless REST API

## Phase 1 — Local Dev
```bash
pip install azure-functions azure-cosmos
func init my-api --python
cd my-api
func new --name items --template "HTTP trigger"
func start
# Test: curl http://localhost:7071/api/items
```

## Phase 2 — Deploy
```bash
cd terraform && terraform init && terraform apply -auto-approve
func azure functionapp publish func-serverless-api-001
```

## Phase 3 — Test
```bash
BASE=https://func-serverless-api-001.azurewebsites.net/api

# Create item
curl -X POST $BASE/items -H "Content-Type: application/json" \
  -d '{"id":"1","name":"test item"}'

# List items
curl $BASE/items

# Get item
curl $BASE/items/1

# Delete item
curl -X DELETE $BASE/items/1
```

## Screenshots to Take
- [ ] Function running locally
- [ ] Function deployed to Azure
- [ ] CRUD operations working via curl
- [ ] Cosmos DB showing items in Data Explorer
