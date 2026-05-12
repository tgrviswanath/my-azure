# Architecture — Project 0.4 Azure Cost Management & Billing

## Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Subscription                        │
│                                                              │
│   ┌─────────────────────────────────────────────────────┐   │
│   │              Azure Resources (tagged)               │   │
│   │                                                      │   │
│   │  [VM: env=dev]  [Storage: env=dev]  [SQL: env=prod] │   │
│   └──────────────────────┬──────────────────────────────┘   │
│                          │ usage data (24-48h delay)         │
│                          ▼                                   │
│   ┌──────────────────────────────────────────────────────┐  │
│   │           Azure Cost Management                      │  │
│   │                                                      │  │
│   │  ┌─────────────────┐   ┌──────────────────────────┐ │  │
│   │  │  Cost Analysis  │   │   Budgets                │ │  │
│   │  │  - By service   │   │   - $20/month limit      │ │  │
│   │  │  - By tag       │   │   - 80% alert → email    │ │  │
│   │  │  - By region    │   │   - 100% alert → email   │ │  │
│   │  └─────────────────┘   └──────────────┬───────────┘ │  │
│   │                                        │             │  │
│   │  ┌─────────────────────────────────────▼───────────┐ │  │
│   │  │         Cost Anomaly Detection                  │ │  │
│   │  │  ML-based: detects unusual spending patterns    │ │  │
│   │  └─────────────────────────────────────┬───────────┘ │  │
│   └────────────────────────────────────────┼─────────────┘  │
│                                            │                 │
│                                            ▼                 │
│   ┌────────────────────────────────────────────────────┐    │
│   │           Azure Monitor Action Group               │    │
│   │                                                    │    │
│   │   📧 Email → you@example.com                       │    │
│   │   📱 SMS → +1-555-0100                             │    │
│   │   🔗 Webhook → Slack/Teams                         │    │
│   └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| Budget | Spending limit with threshold alerts (80%, 100%) |
| Cost Anomaly | ML-based detection of unusual spending patterns |
| Action Group | Defines who gets notified and how (email, SMS, webhook) |
| Cost Analysis | Visual breakdown of spend by service, tag, region |
| Tags | Key-value metadata on resources for cost allocation |
| Scope | Budget can apply to subscription, resource group, or resource |

## Tagging Strategy

```
Every resource should have these tags:
┌─────────────────────────────────────────┐
│  environment  = dev | staging | prod    │
│  project      = azure-lab               │
│  owner        = team-name               │
│  cost-center  = engineering             │
│  auto-shutdown = true | false           │
└─────────────────────────────────────────┘
```

This enables cost reports like:
- "How much did the `dev` environment cost this month?"
- "What is the `azure-lab` project's total spend?"
