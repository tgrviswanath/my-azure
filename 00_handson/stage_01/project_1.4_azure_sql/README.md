# Project 1.4 — Azure SQL Database

## What This Does
Creates and configures an Azure SQL Database with firewall rules, connects via sqlcmd, creates tables, inserts data, and demonstrates geo-replication for disaster recovery.

## Services Used
| Service | Purpose |
|---------|---------|
| Azure SQL Server | Logical server hosting databases |
| Azure SQL Database | Managed relational database (PaaS) |
| SQL Firewall Rules | IP-based access control |
| Geo-Replication | Read replica in secondary region |
| Azure Monitor | Query performance insights |

## How to Deploy
```bash
cd terraform
terraform init
terraform apply -auto-approve

# Get connection details
terraform output sql_server_fqdn
terraform output connection_string

# Connect with sqlcmd
sqlcmd -S <server>.database.windows.net -U sqladmin -P 'YourPass123!' -d labdb

# Run Python demo
pip install pyodbc azure-identity
python code/db_operations.py
```

## Folder Structure
```
project_1.4_azure_sql/
├── README.md
├── steps.md
├── cost_estimate.md
├── docs/
│   └── architecture.md
├── terraform/
│   └── main.tf
└── code/
    └── db_operations.py
```

## Lessons Learned
- Azure SQL is fully managed — no OS patching, automatic backups, HA built-in
- Firewall rules are at the server level, not database level
- `Allow Azure services` rule lets other Azure resources connect without IP whitelisting
- DTU model (Basic/Standard/Premium) is simpler; vCore model is more flexible
- Geo-replication creates a readable secondary — good for read scaling + DR
- Always use parameterized queries — never string-format SQL with user input
- Connection string format: `Server=tcp:<server>.database.windows.net,1433`
- Azure AD authentication is preferred over SQL auth for production

## Connection String Format
```
Server=tcp:<server>.database.windows.net,1433;
Initial Catalog=labdb;
Persist Security Info=False;
User ID=sqladmin;
Password=YourPass123!;
MultipleActiveResultSets=False;
Encrypt=True;
TrustServerCertificate=False;
Connection Timeout=30;
```
