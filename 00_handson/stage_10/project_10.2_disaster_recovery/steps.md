# Steps — Project 10.2 Disaster Recovery Architecture

## Phase 1 — Configure Azure SQL Geo-replication

```bash
# Create primary SQL server
az sql server create \
  --name sql-primary-handson \
  --resource-group rg-dr-primary \
  --location eastus \
  --admin-user sqladmin \
  --admin-password YourPass123!

# Create secondary SQL server
az sql server create \
  --name sql-secondary-handson \
  --resource-group rg-dr-secondary \
  --location westus \
  --admin-user sqladmin \
  --admin-password YourPass123!

# Create database on primary
az sql db create \
  --server sql-primary-handson \
  --resource-group rg-dr-primary \
  --name appdb \
  --service-objective S1
```

---

## Phase 2 — Create Failover Group

```bash
az sql failover-group create \
  --name fg-handson \
  --server sql-primary-handson \
  --resource-group rg-dr-primary \
  --partner-server sql-secondary-handson \
  --partner-resource-group rg-dr-secondary \
  --failover-policy Automatic \
  --grace-period 1

# Verify replication
az sql failover-group show \
  --name fg-handson \
  --server sql-primary-handson \
  --resource-group rg-dr-primary
```

---

## Phase 3 — Configure GRS Storage

```bash
az storage account create \
  --name sthandsondr001 \
  --resource-group rg-dr-primary \
  --location eastus \
  --sku Standard_GRS  # Geo-redundant storage

# Check replication status
az storage account show \
  --name sthandsondr001 \
  --query "geoReplicationStats"
```

---

## Phase 4 — Test Failover

```bash
# Initiate manual failover (for testing)
az sql failover-group set-primary \
  --name fg-handson \
  --server sql-secondary-handson \
  --resource-group rg-dr-secondary

# Verify secondary is now primary
az sql failover-group show \
  --name fg-handson \
  --server sql-secondary-handson \
  --resource-group rg-dr-secondary \
  --query "replicationRole"
```

---

## Phase 5 — Failback

```bash
# Failback to original primary
az sql failover-group set-primary \
  --name fg-handson \
  --server sql-primary-handson \
  --resource-group rg-dr-primary
```

---

## Screenshots to Take
- [ ] Failover group showing primary/secondary
- [ ] Geo-replication lag (should be < 5 seconds)
- [ ] Failover completed — secondary is now primary
- [ ] Application connecting to failover group endpoint
