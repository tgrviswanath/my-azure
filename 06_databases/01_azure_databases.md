# Azure Databases — SQL, Cosmos DB, PostgreSQL & MySQL

## Azure SQL Database

```
Deployment Options:
  Single Database:    Isolated DB with dedicated resources
  Elastic Pool:       Share resources across multiple DBs (cost savings)
  Managed Instance:   Full SQL Server compatibility, VNet injection
  SQL Server on VM:   Full control, IaaS

Service Tiers:
  DTU-based:
    Basic:    5 DTUs, 2GB, dev/test
    Standard: 10-3000 DTUs, 250GB-1TB
    Premium:  125-4000 DTUs, 1TB, in-memory OLTP

  vCore-based (recommended):
    General Purpose:  2-80 vCores, 5.1GB/vCore, 99.99% SLA
    Business Critical: 2-80 vCores, 5.1GB/vCore, in-memory, read replica
    Hyperscale:       Up to 100TB, rapid scale, multiple replicas
```

```bash
# Create SQL Server
az sql server create \
  --name sql-prod-eastus \
  --resource-group $RG \
  --location $LOCATION \
  --admin-user sqladmin \
  --admin-password "$(openssl rand -base64 32)" \
  --enable-public-network false

# Create database
az sql db create \
  --name myapp-db \
  --server sql-prod-eastus \
  --resource-group $RG \
  --service-objective GP_Gen5_4 \
  --zone-redundant true \
  --backup-storage-redundancy Zone

# Configure firewall (allow Azure services)
az sql server firewall-rule create \
  --server sql-prod-eastus \
  --resource-group $RG \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# Enable Advanced Threat Protection
az sql db threat-policy update \
  --name myapp-db \
  --server sql-prod-eastus \
  --resource-group $RG \
  --state Enabled \
  --email-addresses "security@company.com"

# Configure geo-replication
az sql db replica create \
  --name myapp-db \
  --server sql-prod-eastus \
  --resource-group $RG \
  --partner-server sql-dr-westus \
  --partner-resource-group $RG_DR

# Failover group
az sql failover-group create \
  --name fog-myapp \
  --server sql-prod-eastus \
  --resource-group $RG \
  --partner-server sql-dr-westus \
  --failover-policy Automatic \
  --grace-period 1 \
  --add-db myapp-db
```

## Cosmos DB

```
Cosmos DB = globally distributed, multi-model NoSQL database
├── APIs: SQL (Core), MongoDB, Cassandra, Gremlin, Table
├── Consistency levels: Strong, Bounded Staleness, Session, Consistent Prefix, Eventual
├── Global distribution: replicate to any Azure region
├── Automatic indexing: all properties indexed by default
└── SLA: 99.999% availability with multi-region writes

Partitioning:
  Logical partition: items with same partition key
  Physical partition: up to 50GB, 10,000 RU/s
  Choose partition key: high cardinality, even distribution, used in queries
```

```bash
# Create Cosmos DB account
az cosmosdb create \
  --name cosmos-myapp-prod \
  --resource-group $RG \
  --locations regionName=eastus failoverPriority=0 isZoneRedundant=true \
  --locations regionName=westeurope failoverPriority=1 isZoneRedundant=true \
  --default-consistency-level Session \
  --enable-automatic-failover true \
  --enable-multiple-write-locations false \
  --kind GlobalDocumentDB

# Create database and container
az cosmosdb sql database create \
  --account-name cosmos-myapp-prod \
  --resource-group $RG \
  --name myapp-db

az cosmosdb sql container create \
  --account-name cosmos-myapp-prod \
  --resource-group $RG \
  --database-name myapp-db \
  --name orders \
  --partition-key-path "/customerId" \
  --throughput 400

# Enable autoscale
az cosmosdb sql container throughput update \
  --account-name cosmos-myapp-prod \
  --resource-group $RG \
  --database-name myapp-db \
  --name orders \
  --max-throughput 4000
```

## Cosmos DB Consistency Levels

```
Strong:              Read always returns most recent write. Highest latency.
                     Use: financial transactions, inventory

Bounded Staleness:   Reads lag behind writes by K versions or T seconds.
                     Use: global apps needing near-strong consistency

Session (default):   Consistent within a session (client). Most popular.
                     Use: user-specific data, shopping carts

Consistent Prefix:   Reads never see out-of-order writes.
                     Use: social media feeds, event sourcing

Eventual:            No ordering guarantee. Lowest latency, highest availability.
                     Use: likes/views counters, non-critical data
```

## Azure Database for PostgreSQL

```bash
# Create Flexible Server (recommended)
az postgres flexible-server create \
  --name psql-myapp-prod \
  --resource-group $RG \
  --location $LOCATION \
  --admin-user pgadmin \
  --admin-password "$(openssl rand -base64 32)" \
  --sku-name Standard_D4s_v3 \
  --tier GeneralPurpose \
  --storage-size 128 \
  --version 15 \
  --high-availability ZoneRedundant \
  --zone 1 \
  --standby-zone 2 \
  --backup-retention 7 \
  --geo-redundant-backup Enabled \
  --vnet vnet-app-prod \
  --subnet snet-db \
  --private-dns-zone myapp.private.postgres.database.azure.com

# Create database
az postgres flexible-server db create \
  --server-name psql-myapp-prod \
  --resource-group $RG \
  --database-name myapp

# Configure parameters
az postgres flexible-server parameter set \
  --server-name psql-myapp-prod \
  --resource-group $RG \
  --name max_connections \
  --value 200

# Enable read replica
az postgres flexible-server replica create \
  --replica-name psql-myapp-replica \
  --source-server psql-myapp-prod \
  --resource-group $RG \
  --location westeurope
```

## Interview Questions

### Q1: What are the Cosmos DB consistency levels and when do you use each?
**Answer:**
- **Strong**: Linearizable reads. Use for financial transactions where accuracy is critical.
- **Bounded Staleness**: Configurable lag. Use for global apps needing near-strong consistency.
- **Session** (default): Consistent within a client session. Best for most apps (user data, carts).
- **Consistent Prefix**: No out-of-order reads. Use for event sourcing, social feeds.
- **Eventual**: Highest availability, lowest latency. Use for counters, non-critical data.

### Q2: How do you choose a partition key in Cosmos DB?
**Answer:**
Good partition key:
1. **High cardinality**: many distinct values (userId, orderId — not status, country)
2. **Even distribution**: avoid hot partitions (don't use timestamp as sole key)
3. **Used in queries**: include in WHERE clauses to avoid cross-partition queries
4. **Immutable**: don't change after creation
Examples: `/userId`, `/tenantId`, `/productId`

### Q3: What is the difference between Azure SQL Database and SQL Managed Instance?
**Answer:**
- **SQL Database**: Fully managed PaaS. Some SQL Server features not available. Best for new cloud-native apps.
- **SQL Managed Instance**: Near 100% SQL Server compatibility. VNet injection. Supports SQL Agent, CLR, linked servers. Best for lift-and-shift migrations from on-premises SQL Server.

### Q4: How do you achieve high availability in Azure SQL Database?
**Answer:**
1. **Zone-redundant deployment**: replicas across availability zones (Business Critical/Hyperscale)
2. **Failover groups**: automatic failover to secondary region
3. **Active geo-replication**: up to 4 readable secondaries in different regions
4. **Business Critical tier**: built-in Always On availability group, 3 replicas
5. **Backup**: automated backups (7-35 days), geo-redundant backup storage
