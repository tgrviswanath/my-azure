# Azure Hands-On Projects — Complete Roadmap

This folder contains 50+ hands-on Azure projects organized into 11 stages, progressing from beginner to expert level.

## Structure

```
00_handson/
├── stage_00/  Local dev, Linux, Git, Billing (4 projects) ✅ COMPLETE
├── stage_01/  Core Azure services (5 projects) ✅ COMPLETE
├── stage_02/  Networking & Infrastructure (5 projects) ⚠️ PARTIAL
├── stage_03/  Terraform & IaC (5 projects) ⚠️ STRUCTURE ONLY
├── stage_04/  Serverless & Event-driven (6 projects) ⚠️ STRUCTURE ONLY
├── stage_05/  Containers & Modern Deployment (7 projects) ⚠️ STRUCTURE ONLY
├── stage_06/  CI/CD & DevOps (5 projects) ⚠️ STRUCTURE ONLY
├── stage_07/  Monitoring & Observability (5 projects) ⚠️ STRUCTURE ONLY
├── stage_08/  Security & Governance (6 projects) ⚠️ STRUCTURE ONLY
├── stage_09/  Data Engineering & Analytics (9 projects) ⚠️ STRUCTURE ONLY
└── stage_10/  Advanced Cloud Architecture (5 projects) ⚠️ STRUCTURE ONLY
```

## Completed Projects (Stage 0 & 1)

### Stage 0 — Foundations
- ✅ 0.1 Local Dev Setup (Azurite, Cosmos Emulator, Functions Core Tools)
- ✅ 0.2 Linux Lab (SSH, Nginx, cron, logs)
- ✅ 0.3 Git Workflow (branching, PRs, GitHub Actions)
- ✅ 0.4 Billing (budgets, cost alerts, tagging)

### Stage 1 — Core Azure
- ✅ 1.1 Static Website (Storage + CDN)
- ✅ 1.2 VM Web Server (Ubuntu + Nginx)
- ✅ 1.3 IAM (Azure AD, RBAC, Managed Identity)
- ✅ 1.4 Azure SQL (database, geo-replication)
- ✅ 1.5 Python Automation (azure-sdk scripts)

### Stage 2 — Networking (Partial)
- ✅ 2.1 Custom VNet (3-tier, NAT Gateway, NSGs)
- ⚠️ 2.2 Multi-tier App (Front Door + App Gateway + VMSS + SQL)
- ⚠️ 2.3 App Gateway vs Load Balancer
- ⚠️ 2.4 DNS Routing (Traffic Manager)
- ⚠️ 2.5 Failure Simulation

## Next Steps

All directory structures for stages 2-10 have been created. To complete:

1. **Stage 2-10 Projects**: Each needs:
   - README.md (overview, services, architecture)
   - steps.md (phase-by-phase CLI + portal instructions)
   - terraform/main.tf (IaC deployment)
   - cost_estimate.md (monthly cost breakdown)
   - docs/architecture.md (diagram + key concepts)

2. **Follow AWS Pattern**: Reference `D:\1.projects\AI\my-aws\01_new_handson` for file structure and content style.

3. **Azure-Specific Adaptations**:
   - Replace AWS services with Azure equivalents
   - Use Azure CLI instead of AWS CLI
   - Use azurerm provider instead of aws provider
   - Adjust pricing to Azure cost model

## Quick Start

```bash
# Navigate to any project
cd stage_01/project_1.1_static_website

# Read the README
cat README.md

# Follow steps
cat steps.md

# Deploy with Terraform
cd terraform
terraform init
terraform apply -auto-approve
```

## Cost Awareness

Every project includes `cost_estimate.md` with:
- Monthly cost breakdown
- Free tier eligibility
- Cost-saving tips

**Total cost for all Stage 0-1 projects**: ~$15-20/month (or $0 with free tier)

## Learning Path

| Week | Focus | Projects |
|------|-------|---------|
| 1 | Foundations | Stage 0 (all 4) |
| 2 | Core Azure | Stage 1 (all 5) |
| 3-4 | Networking | Stage 2 (all 5) |
| 5-6 | Terraform | Stage 3 (all 5) |
| 7-8 | Serverless | Stage 4 (all 6) |
| 9-10 | Containers | Stage 5 (all 7) |
| 11-12 | CI/CD | Stage 6 (all 5) |
| 13-14 | Monitoring | Stage 7 (all 5) |
| 15-16 | Security | Stage 8 (all 6) |
| 17-20 | Data Engineering | Stage 9 (all 9) |
| 21-24 | Advanced | Stage 10 (all 5) |

## Status Summary

- ✅ **Completed**: 9 projects (Stage 0-1)
- ⚠️ **Partial**: 1 project (Stage 2.1)
- 📁 **Structure Only**: 47 projects (Stages 2.2-10.5)

All folder structures are in place. Content creation for stages 2-10 can follow the established pattern from stages 0-1.
