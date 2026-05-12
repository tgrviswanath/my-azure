# Steps — Project 4.6 Durable Functions Workflow

## Phase 1 — Run Locally
```bash
pip install azure-functions azure-durable-functions
func start

# Start workflow
curl -X POST http://localhost:7071/api/orchestrators/document_workflow \
  -H "Content-Type: application/json" \
  -d '{"document_id":"doc-001","filename":"report.pdf"}'

# Check status (use instanceId from response)
curl http://localhost:7071/runtime/webhooks/durabletask/instances/<instanceId>
```

## Phase 2 — Deploy
```bash
cd terraform && terraform init && terraform apply -auto-approve
func azure functionapp publish func-durable-workflow-001
```

## Screenshots to Take
- [ ] Workflow started and instanceId returned
- [ ] Status showing each step completing
- [ ] Final status: completed
