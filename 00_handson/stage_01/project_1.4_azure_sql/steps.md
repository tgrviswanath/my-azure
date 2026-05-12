# Steps — Project 1.4 Azure SQL Database

## Phase 1 — Create SQL Server + Database

### 1.1 Deploy with Terraform
```bash
cd terraform
terraform init
terraform apply -auto-approve
terraform output
```

### 1.2 Or create manually via CLI
```bash
RESOURCE_GROUP="azure-sql-lab-rg"
SERVER_NAME="sql-lab-server-$(date +%s)"
LOCATION="eastus"
ADMIN_USER="sqladmin"
ADMIN_PASS="YourPass123!"

az group create --name $RESOURCE_GROUP --location $LOCATION

# Create SQL Server
az sql server create \
  --name $SERVER_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --admin-user $ADMIN_USER \
  --admin-password $ADMIN_PASS

# Create database (Basic tier — cheapest)
az sql db create \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --name labdb \
  --service-objective Basic
```

---

## Phase 2 — Configure Firewall

### 2.1 Allow your current IP
```bash
MY_IP=$(curl -s ifconfig.me)

az sql server firewall-rule create \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --name AllowMyIP \
  --start-ip-address $MY_IP \
  --end-ip-address $MY_IP
```

### 2.2 Allow Azure services (for Azure-to-Azure connections)
```bash
az sql server firewall-rule create \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0
```

### 2.3 List firewall rules
```bash
az sql server firewall-rule list \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --output table
```

---

## Phase 3 — Connect with sqlcmd

### 3.1 Install sqlcmd
```bash
# macOS
brew install sqlcmd

# Ubuntu
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
sudo apt-get install -y mssql-tools

# Windows — included with SQL Server tools
```

### 3.2 Connect to the database
```bash
SERVER_FQDN=$(az sql server show \
  --name $SERVER_NAME \
  --resource-group $RESOURCE_GROUP \
  --query fullyQualifiedDomainName -o tsv)

sqlcmd -S $SERVER_FQDN -U $ADMIN_USER -P $ADMIN_PASS -d labdb
```

### 3.3 Run a test query
```sql
SELECT @@VERSION;
GO
SELECT GETDATE() AS CurrentTime;
GO
```

---

## Phase 4 — Create Tables and Insert Data

### 4.1 Create orders table
```sql
CREATE TABLE orders (
    id INT IDENTITY(1,1) PRIMARY KEY,
    customer_name NVARCHAR(100) NOT NULL,
    product NVARCHAR(100) NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    status NVARCHAR(20) DEFAULT 'pending',
    created_at DATETIME2 DEFAULT GETDATE()
);
GO
```

### 4.2 Insert sample data
```sql
INSERT INTO orders (customer_name, product, amount, status) VALUES
    ('Alice Johnson', 'Azure VM B2s', 30.37, 'completed'),
    ('Bob Smith', 'Azure Storage 100GB', 2.30, 'completed'),
    ('Carol White', 'Azure SQL Basic', 4.99, 'pending'),
    ('David Brown', 'Azure CDN 50GB', 4.35, 'completed'),
    ('Eve Davis', 'Azure Functions', 0.20, 'pending');
GO
```

### 4.3 Query the data
```sql
SELECT * FROM orders ORDER BY created_at DESC;
GO
SELECT status, COUNT(*) as count, SUM(amount) as total
FROM orders GROUP BY status;
GO
```

### 4.4 Run Python demo
```bash
pip install pyodbc
python code/db_operations.py
```

---

## Phase 5 — Enable Geo-Replication

### 5.1 Create a geo-replica in West US
```bash
az sql db replica create \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --name labdb \
  --partner-server sql-lab-server-westus \
  --partner-resource-group $RESOURCE_GROUP
```

### 5.2 List replicas
```bash
az sql db replica list-links \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --name labdb \
  --output table
```

---

## Screenshots to Take
- [ ] SQL Server and database created in Azure Portal
- [ ] Firewall rules showing your IP allowed
- [ ] sqlcmd connected and showing @@VERSION
- [ ] Orders table with 5 rows
- [ ] Python db_operations.py output
