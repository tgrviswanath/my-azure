# Security & Cost Optimization Interview Questions

## Security Questions

### Q1: What is the difference between Azure AD and Active Directory Domain Services?
**Answer:**
| | Azure AD (Entra ID) | AD DS (on-premises) |
|---|---|---|
| Protocol | OAuth 2.0, OIDC, SAML | Kerberos, NTLM, LDAP |
| Structure | Flat (no OUs, GPOs) | Hierarchical (OUs, GPOs) |
| Join | Azure AD Join, Hybrid Join | Domain Join |
| Use case | Cloud apps, SaaS | On-premises apps, file servers |
| Management | Azure portal, Graph API | ADUC, Group Policy |

Azure AD is NOT a cloud version of AD DS — they're different products for different purposes.

---

### Q2: Explain the principle of least privilege and how to implement it in Azure.
**Answer:**
Least privilege = grant only the minimum permissions needed to perform a task.

Implementation:
1. **RBAC**: Assign built-in roles at lowest scope (resource > RG > subscription)
2. **Custom roles**: Create roles with only needed actions
3. **PIM**: Just-in-time access for privileged roles (request → approve → time-limited)
4. **Managed Identity**: No standing credentials, auto-rotated
5. **Conditional Access**: Require MFA for sensitive operations
6. **Access reviews**: Regularly review and remove unnecessary access
7. **Service principals**: Scope to specific resource groups, not entire subscription

---

### Q3: What is Azure Policy and how does it differ from RBAC?
**Answer:**
- **RBAC**: Controls WHO can perform actions (access control). Prevents unauthorized users from creating resources.
- **Azure Policy**: Controls WHAT resources can be created/configured (governance). Ensures resources comply with organizational standards.

They complement each other:
- RBAC: "Only admins can create VMs"
- Policy: "All VMs must use Premium SSD and be in approved regions"

Policy effects: `Deny`, `Audit`, `Append`, `Modify`, `DeployIfNotExists`, `AuditIfNotExists`

---

### Q4: How do you protect against SQL injection in Azure?
**Answer:**
1. **Parameterized queries**: Never concatenate user input into SQL
2. **Azure SQL Threat Detection**: Detects anomalous queries, alerts on injection attempts
3. **Azure Defender for SQL**: Advanced threat protection, vulnerability assessment
4. **Firewall rules**: Restrict access to known IPs/VNets
5. **Private endpoints**: No public internet access to SQL
6. **Least privilege**: App uses read-only account where possible
7. **Input validation**: Validate and sanitize all inputs before DB operations

---

### Q5: What is the difference between encryption at rest and in transit?
**Answer:**
- **At rest**: Data stored on disk is encrypted. Azure uses SSE (Storage Service Encryption) with AES-256 by default. Can use Microsoft-managed keys (MMK) or customer-managed keys (CMK) in Key Vault.
- **In transit**: Data moving over network is encrypted. Azure enforces TLS 1.2+ for all services. Set `--https-only true` on storage, `--min-tls-version TLS1_2` on SQL.
- **In use**: Data being processed. Azure Confidential Computing uses hardware-based TEEs (Trusted Execution Environments).

---

### Q6: What is a Service Principal and when do you use it vs Managed Identity?
**Answer:**
- **Service Principal**: Azure AD identity for applications/services. Has credentials (password or certificate) that must be managed, rotated, and secured.
- **Managed Identity**: Azure-managed service principal. No credentials to manage — Azure handles rotation automatically.

Use Managed Identity when: running on Azure (VMs, App Service, Functions, AKS)
Use Service Principal when: running outside Azure (GitHub Actions, on-premises, other clouds), or when you need cross-tenant access

---

### Q7: How do you implement network segmentation in Azure?
**Answer:**
1. **VNet subnets**: Separate tiers (web, app, data, management)
2. **NSGs**: Deny-all default, allow only required traffic
3. **Azure Firewall**: Centralized policy, FQDN filtering, IDPS
4. **Private Endpoints**: Services accessible only from VNet
5. **Service Endpoints**: Restrict storage/SQL to specific subnets
6. **Application Security Groups**: Group VMs logically for NSG rules
7. **Network Watcher**: Monitor and diagnose network issues

---

## Cost Optimization Questions

### Q8: What are the main ways to reduce Azure VM costs?
**Answer:**
1. **Reserved Instances**: 1-year (~40% savings) or 3-year (~60-72%) commitment
2. **Spot VMs**: Up to 90% savings for fault-tolerant workloads (can be evicted)
3. **Azure Hybrid Benefit**: Use existing Windows Server/SQL Server licenses
4. **Right-sizing**: Use Azure Advisor to identify over-provisioned VMs
5. **Auto-shutdown**: Schedule VMs to stop during off-hours
6. **B-series VMs**: Burstable, cheaper for variable workloads
7. **Deallocate vs Stop**: Always deallocate to stop compute billing

---

### Q9: How do you implement a cost governance strategy in Azure?
**Answer:**
**Visibility**:
- Azure Cost Management + Billing dashboards
- Cost allocation tags (Environment, Team, Project, CostCenter)
- Budgets with email/action group alerts
- Cost anomaly detection

**Accountability**:
- Separate subscriptions per team/environment
- Chargeback/showback reports
- Monthly cost reviews with teams

**Optimization**:
- Azure Advisor cost recommendations
- Reserved Instances for predictable workloads
- Storage lifecycle policies
- Regular right-sizing reviews
- Delete unused resources (orphaned disks, unused IPs)

**Governance**:
- Azure Policy: enforce tagging, restrict expensive SKUs
- Management Groups: apply policies across subscriptions
- Budgets: hard limits with automated responses

---

### Q10: What is the difference between Reserved Instances and Savings Plans?
**Answer:**
- **Reserved Instances**: Commit to specific VM size, region, and OS for 1 or 3 years. Up to 72% savings. Inflexible — tied to specific configuration.
- **Azure Savings Plans**: Commit to hourly spend amount for 1 or 3 years. Applies to any VM size/region/OS. More flexible. Up to 65% savings.
- **Spot VMs**: Use unused capacity. Up to 90% savings. Can be evicted with 30s notice. For fault-tolerant workloads only.

Use Reserved Instances for: predictable, stable workloads with known configuration.
Use Savings Plans for: variable workloads, multiple regions, mixed VM sizes.

---

### Q11: How do you optimize Azure Storage costs?
**Answer:**
1. **Lifecycle policies**: Auto-move data Hot → Cool (30 days) → Archive (90 days) → Delete (365 days)
2. **Right redundancy**: LRS for dev/test, ZRS for production (not GRS unless needed)
3. **Access tier**: Set appropriate default tier (Cool for infrequent access)
4. **Delete orphaned resources**: Unused disks, old snapshots, empty containers
5. **Compression**: Compress data before storing
6. **Deduplication**: Use Azure Backup deduplication
7. **Reserved capacity**: 1-year commitment for predictable storage

---

### Q12: A company's Azure bill increased 40% last month. How do you investigate?
**Answer:**
1. **Azure Cost Management**: Check cost by service, resource group, tag
2. **Cost anomaly detection**: Review anomaly alerts
3. **Activity log**: Check for new resource deployments
4. **Advisor**: Check for new recommendations
5. **Common causes**:
   - New resources deployed without approval
   - Dev/test resources left running
   - Data transfer costs (cross-region, egress)
   - Storage tier not optimized
   - Auto-scaling triggered unexpectedly
   - Reserved Instances expired
6. **Immediate actions**: Set budget alerts, tag all resources, review auto-scaling settings

---

## Scenario-Based Security Questions

### S1: Your App Service is returning 401 errors when accessing Key Vault. How do you troubleshoot?
**Answer:**
1. Verify Managed Identity is enabled: `az webapp identity show --name $APP --resource-group $RG`
2. Check RBAC assignment: `az role assignment list --scope $KV_ID --assignee $PRINCIPAL_ID`
3. Verify role is "Key Vault Secrets User" (not just "Reader")
4. Check Key Vault network rules — is App Service VNet allowed?
5. Check Key Vault firewall — is "Allow trusted Microsoft services" enabled?
6. Check App Service app setting format: `@Microsoft.KeyVault(VaultName=...;SecretName=...)`
7. Check Key Vault soft delete — was secret accidentally deleted?
8. Review Key Vault diagnostic logs for access denied events

### S2: How do you respond to a suspected security breach in Azure?
**Answer:**
1. **Contain**: Isolate affected resources (NSG deny-all, revoke credentials)
2. **Assess**: Review Azure AD sign-in logs, activity logs, Defender alerts
3. **Investigate**: Use Microsoft Sentinel for SIEM analysis, check audit logs
4. **Remediate**: Rotate compromised credentials, patch vulnerabilities
5. **Recover**: Restore from clean backup if needed
6. **Post-incident**: Root cause analysis, update security controls
7. **Report**: Notify stakeholders, regulatory bodies if required (GDPR 72-hour rule)
