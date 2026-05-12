# Project 4.6 — Durable Functions Workflow

## What This Does
Orchestrates a multi-step workflow: Upload → Validate → Process → Notify using Durable Functions.

## How to Run
```bash
func start
curl -X POST http://localhost:7071/api/orchestrators/document_workflow \
  -d '{"document_id":"doc-001","filename":"report.pdf"}'
```

## Lessons Learned
- Durable Functions maintain state across long-running workflows
- Orchestrator functions must be deterministic (no I/O directly)
- Activity functions do the actual work
- Fan-out/fan-in pattern for parallel processing
