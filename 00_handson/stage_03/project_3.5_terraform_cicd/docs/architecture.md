# Architecture — Terraform CI/CD

## ASCII Diagram

```
  Developer
     │
     │ git push feature/xxx
     ▼
  ┌─────────────────────────────────────────────────────────────────┐
  │  GitHub Repository                                               │
  │                                                                   │
  │  PR opened/updated                                               │
  │     │                                                             │
  │     ▼                                                             │
  │  ┌──────────────────────────────────────────────────────────┐   │
  │  │  GitHub Actions: terraform-plan.yml                       │   │
  │  │                                                            │   │
  │  │  1. actions/checkout@v4                                   │   │
  │  │  2. hashicorp/setup-terraform@v3                          │   │
  │  │  3. az login (using AZURE_* secrets)                      │   │
  │  │  4. terraform init (remote state on Azure Storage)        │   │
  │  │  5. terraform fmt --check                                 │   │
  │  │  6. terraform validate                                    │   │
  │  │  7. terraform plan -out=tfplan                            │   │
  │  │  8. Post plan output as PR comment                        │   │
  │  └──────────────────────────────────────────────────────────┘   │
  │                                                                   │
  │  PR approved + merged to main                                    │
  │     │                                                             │
  │     ▼                                                             │
  │  ┌──────────────────────────────────────────────────────────┐   │
  │  │  GitHub Actions: terraform-apply.yml                      │   │
  │  │                                                            │   │
  │  │  1. actions/checkout@v4                                   │   │
  │  │  2. hashicorp/setup-terraform@v3                          │   │
  │  │  3. az login (using AZURE_* secrets)                      │   │
  │  │  4. terraform init (remote state on Azure Storage)        │   │
  │  │  5. terraform apply -auto-approve                         │   │
  │  │  6. terraform output (post to job summary)                │   │
  │  └──────────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────────┘
                              │
                              │ ARM API calls
                              ▼
  ┌─────────────────────────────────────────────────────────────────┐
  │  Azure                                                           │
  │                                                                   │
  │  Service Principal (sp-terraform-cicd)                          │
  │  Role: Contributor on subscription                               │
  │                                                                   │
  │  State: Azure Storage (stterraformstateXXXXXX/tfstate/)         │
  │                                                                   │
  │  Resources: Whatever main.tf defines                             │
  └─────────────────────────────────────────────────────────────────┘
```

## Workflow Files

```
.github/
└── workflows/
    ├── terraform-plan.yml    ← Triggered on: pull_request
    └── terraform-apply.yml   ← Triggered on: push to main
```

## Key Concepts

| Concept | Explanation |
|---|---|
| Service Principal | Azure identity for GitHub Actions. Has Contributor role on subscription. |
| GitHub Secrets | Encrypted storage for AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, etc. |
| `hashicorp/setup-terraform` | GitHub Action that installs Terraform in the runner |
| `concurrency` | Prevents two workflows from running terraform simultaneously |
| Plan as PR comment | Posts terraform plan output to the PR so reviewers can see what will change |
| Environment protection | Require manual approval before applying to prod (GitHub Environments feature) |
| OIDC authentication | Preferred over client secret — uses federated identity, no secret rotation needed |
