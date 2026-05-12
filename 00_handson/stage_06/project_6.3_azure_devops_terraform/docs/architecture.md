# Architecture — Project 6.3 Azure DevOps + Terraform Pipeline

## Diagram

```
Developer
    │ git push / PR
    ▼
Azure DevOps Repo
    │
    ▼
Azure DevOps Pipeline (azure-pipelines.yml)
    │
    ├── Stage 1: Validate
    │     ├── terraform fmt -check
    │     └── terraform validate
    │
    ├── Stage 2: Plan (runs on every push/PR)
    │     ├── terraform init (azurerm backend)
    │     ├── terraform plan -out=plan.tfplan
    │     └── publish plan as artifact
    │
    ├── Stage 3: Approval Gate (manual — prod only)
    │     └── wait for human approval
    │
    └── Stage 4: Apply (runs on merge to main)
          ├── download plan artifact
          └── terraform apply plan.tfplan
                │
                ▼
          Azure Resources
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Service Connection | ADO credential to authenticate to Azure |
| azurerm backend | Terraform state stored in Azure Blob Storage |
| Blob lease | Azure Storage lease = Terraform state lock |
| Approval gate | Manual approval before apply in production |
| Plan artifact | Saved plan file — ensures apply matches reviewed plan |
