# AZ-104 & AZ-204 Interview Questions

## AZ-104 — Azure Administrator

### Identity & Governance

**Q1: How do you implement MFA for all users in Azure AD?**
1. Azure AD → Security → Conditional Access
2. Create policy: All users, All cloud apps
3. Grant: Require multi-factor authentication
4. Enable policy
Or use Security Defaults (simpler, less flexible).

**Q2: What is Privileged Identity Management (PIM)?**
PIM provides just-in-time privileged access. Users request elevation for a time-limited period. Requires approval, MFA, and justification. Provides audit trail. Use for: Global Admin, Subscription Owner, Key Vault access.

**Q3: How do you move a resource to a different resource group?**
```bash
az resource move \
  --destination-group new-rg \
  --ids /subscriptions/$SUB/resourceGroups/old-rg/providers/Microsoft.Compute/virtualMachines/myvm
```
Note: Some resources can't be moved. Check with `az resource list-move-resources`.

**Q4: What is Azure Policy vs RBAC?**
- **RBAC**: Controls WHO can do WHAT (access control)
- **Azure Policy**: Controls WHAT resources can be created/configured (governance)
They complement each other. RBAC prevents unauthorized actions; Policy ensures compliant configurations.

### Compute

**Q5: How do you resize a VM?**
```bash
# Check available sizes in region
az vm list-vm-resize-options --resource-group $RG --name $VM_NAME

# Resize (requires deallocation if new size not in same cluster)
az vm resize --resource-group $RG --name $VM_NAME --size Standard_D4s_v5
```

**Q6: What is Azure Bastion and why use it?**
Managed PaaS service providing secure RDP/SSH to VMs without public IPs. Benefits: no public IP on VMs, no NSG rules for RDP/SSH, protection against port scanning, session recording (Premium). Deploy in AzureBastionSubnet (/27 minimum).

**Q7: How do you configure VM auto-shutdown?**
```bash
az vm auto-shutdown \
  --resource-group $RG \
  --name $VM_NAME \
  --time 1900 \
  --email "admin@company.com"
```

### Storage

**Q8: What is the difference between Azure Files and Azure Blob Storage?**
- **Azure Files**: SMB/NFS file shares. Mountable on Windows/Linux/macOS. Use for: lift-and-shift file servers, shared application data.
- **Azure Blob**: Object storage. REST API access. Use for: unstructured data, backups, static websites, media.

**Q9: How do you configure storage account firewall?**
```bash
az storage account update \
  --name $STORAGE_NAME \
  --resource-group $RG \
  --default-action Deny

az storage account network-rule add \
  --account-name $STORAGE_NAME \
  --resource-group $RG \
  --vnet-name $VNET_NAME \
  --subnet $SUBNET_NAME
```

### Networking

**Q10: What is the difference between UDR and BGP routing?**
- **UDR** (User Defined Routes): Static routes you define. Override Azure's default routing. Use to force traffic through NVA/firewall.
- **BGP**: Dynamic routing protocol. Used with VPN Gateway and ExpressRoute to exchange routes with on-premises.

**Q11: How do you troubleshoot VM connectivity issues?**
1. Check NSG rules (inbound/outbound)
2. Check effective routes (`az network nic show-effective-route-table`)
3. Check effective NSG rules (`az network nic list-effective-nsg`)
4. Use Network Watcher: IP flow verify, next hop, packet capture
5. Check VM firewall (OS-level)
6. Verify DNS resolution

---

## AZ-204 — Azure Developer

### App Service

**Q12: How do you configure connection strings in App Service?**
```bash
# App settings (environment variables)
az webapp config appsettings set \
  --name $APP_NAME \
  --resource-group $RG \
  --settings DATABASE_URL="@Microsoft.KeyVault(VaultName=$KV_NAME;SecretName=DbUrl)"

# Connection strings (special handling for .NET)
az webapp config connection-string set \
  --name $APP_NAME \
  --resource-group $RG \
  --connection-string-type SQLAzure \
  --settings DefaultConnection="Server=..."
```

**Q13: What is Easy Auth in App Service?**
Built-in authentication/authorization (no code changes needed). Supports: Azure AD, Microsoft, Google, Facebook, Twitter, GitHub. Validates tokens before requests reach your app. Configure in: Authentication blade in portal.

### Azure Functions

**Q14: What is the difference between function.json bindings and SDK-style bindings?**
- **function.json**: Declarative JSON configuration. Older approach.
- **SDK-style** (v4 Node.js, isolated .NET): Code-based bindings using decorators/attributes. More type-safe, better IDE support. Recommended for new projects.

**Q15: How do you handle long-running operations in Azure Functions?**
Use **Durable Functions**:
- Orchestrator function coordinates workflow
- Activity functions do the actual work
- Supports: fan-out/fan-in, human interaction, monitoring, sagas
- State persisted in Azure Storage (checkpointing)

### Cosmos DB

**Q16: What is the Request Unit (RU) in Cosmos DB?**
RU is the currency for Cosmos DB operations. 1 RU = cost to read a 1KB item. Write costs ~5x read. Complex queries cost more. You provision RU/s (throughput) or use serverless (pay per RU consumed). Monitor RU consumption to right-size.

**Q17: How do you implement optimistic concurrency in Cosmos DB?**
Use the `_etag` property. Include `If-Match: {etag}` header in update requests. If document changed since read, returns 412 Precondition Failed. Retry with fresh read.

### Security

**Q18: How do you use Managed Identity to access Key Vault from App Service?**
```javascript
const { DefaultAzureCredential } = require('@azure/identity');
const { SecretClient } = require('@azure/keyvault-secrets');

// DefaultAzureCredential automatically uses Managed Identity in Azure
const credential = new DefaultAzureCredential();
const client = new SecretClient(
  `https://${process.env.KEY_VAULT_NAME}.vault.azure.net`,
  credential
);

const secret = await client.getSecret('DatabasePassword');
console.log(secret.value);
```
No credentials in code. Assign "Key Vault Secrets User" role to the app's managed identity.

---

## Scenario-Based Questions

### S1: Application is slow. How do you diagnose?
1. **Application Insights**: check slow requests, dependencies, exceptions
2. **Live Metrics**: real-time performance
3. **Profiler**: CPU profiling for .NET/Java
4. **Snapshot Debugger**: capture state at exception
5. **Log Analytics**: KQL queries for patterns
6. **Azure Monitor**: resource metrics (CPU, memory, connections)
7. **Database**: Query Performance Insight, slow query log

### S2: How do you implement blue/green deployment for App Service?
1. Create staging slot: `az webapp deployment slot create --slot staging`
2. Deploy new version to staging
3. Test staging URL
4. Swap: `az webapp deployment slot swap --slot staging`
5. Monitor production
6. If issues: swap back (instant rollback)
7. Use slot settings for environment-specific config

### S3: How do you secure an API in Azure?
1. **Azure API Management**: rate limiting, authentication, transformation
2. **Azure AD**: OAuth 2.0 / JWT validation
3. **App Service Easy Auth**: built-in authentication
4. **Managed Identity**: service-to-service auth
5. **Private endpoints**: no public internet access
6. **WAF**: protect against OWASP top 10
7. **Key Vault**: store API keys and secrets

### S4: Cost optimization for a development environment?
1. **Auto-shutdown**: VMs off at 7 PM, on at 8 AM
2. **Dev/Test subscription**: discounted rates
3. **B-series VMs**: burstable, cheaper than D-series
4. **Spot VMs**: for CI/CD agents
5. **Azure Dev/Test Labs**: manage dev environments
6. **Delete unused resources**: orphaned disks, old snapshots
7. **Reserved Instances**: for always-on dev servers
8. **Budget alerts**: notify when spending exceeds threshold
