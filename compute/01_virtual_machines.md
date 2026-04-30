# Azure Compute — Virtual Machines Deep Dive

## VM Architecture

```
Azure VM
├── Compute (vCPUs, RAM) — billed per second when running
├── OS Disk (managed disk, persists after stop)
├── Data Disks (optional, attached managed disks)
├── Network Interface (NIC) → VNet → Subnet
├── Public IP (optional)
└── NSG (Network Security Group)

VM States:
  Running    → billed for compute + storage
  Stopped    → billed for compute + storage (OS stopped, Azure still allocated)
  Deallocated → billed for storage only (compute released)
```

## VM Series & Sizes

```
Series  | Use Case                    | Examples
--------|-----------------------------|-----------------------
B       | Burstable, dev/test         | B1s, B2s, B4ms
D       | General purpose             | D2s_v5, D4s_v5
E       | Memory optimized            | E4s_v5, E8s_v5
F       | Compute optimized           | F4s_v2, F8s_v2
G       | Memory + storage optimized  | G2, G4
H       | High performance compute    | H8, H16
L       | Storage optimized           | L8s_v3, L16s_v3
M       | Very large memory           | M128ms
N       | GPU                         | NC6, NV6, ND40rs_v2
```

## VM Disks

```
Disk Type    | Max IOPS  | Max Throughput | Use Case
-------------|-----------|----------------|------------------
Ultra Disk   | 160,000   | 2,000 MB/s     | Mission-critical DBs
Premium SSD  | 20,000    | 900 MB/s       | Production workloads
Standard SSD | 6,000     | 750 MB/s       | Web servers, dev
Standard HDD | 2,000     | 500 MB/s       | Backup, archive

Disk Caching:
  None:      Write-through, no cache (databases)
  ReadOnly:  Cache reads (OS disk, read-heavy)
  ReadWrite: Cache reads+writes (OS disk only, risky for data)
```

## High Availability Options

```
Single VM:          SLA 99.9% (Premium SSD)
Availability Set:   SLA 99.95% (2+ VMs, same datacenter)
Availability Zones: SLA 99.99% (2+ VMs, different datacenters)
VMSS (Scale Sets):  Auto-scaling + HA
```

## VM Scale Sets (VMSS)

```bash
# Create VMSS
az vmss create \
  --resource-group $RG \
  --name vmss-web-prod \
  --image Ubuntu2204 \
  --vm-sku Standard_B2s \
  --instance-count 2 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --upgrade-policy-mode automatic \
  --zones 1 2 3

# Configure autoscale
az monitor autoscale create \
  --resource-group $RG \
  --resource vmss-web-prod \
  --resource-type Microsoft.Compute/virtualMachineScaleSets \
  --name autoscale-web \
  --min-count 2 \
  --max-count 10 \
  --count 2

# Scale out rule: CPU > 70% for 5 min
az monitor autoscale rule create \
  --resource-group $RG \
  --autoscale-name autoscale-web \
  --condition "Percentage CPU > 70 avg 5m" \
  --scale out 2

# Scale in rule: CPU < 30% for 10 min
az monitor autoscale rule create \
  --resource-group $RG \
  --autoscale-name autoscale-web \
  --condition "Percentage CPU < 30 avg 10m" \
  --scale in 1
```

## Custom Script Extension

```bash
# Run script on VM after creation
az vm extension set \
  --resource-group $RG \
  --vm-name $VM_NAME \
  --name CustomScript \
  --publisher Microsoft.Azure.Extensions \
  --settings '{"fileUris":["https://raw.githubusercontent.com/user/repo/main/setup.sh"],"commandToExecute":"bash setup.sh"}'
```

## VM Backup

```bash
# Create Recovery Services vault
az backup vault create \
  --name rsv-backup-prod \
  --resource-group $RG \
  --location $LOCATION

# Enable backup for VM
az backup protection enable-for-vm \
  --resource-group $RG \
  --vault-name rsv-backup-prod \
  --vm $VM_NAME \
  --policy-name DefaultPolicy

# Trigger backup
az backup protection backup-now \
  --resource-group $RG \
  --vault-name rsv-backup-prod \
  --container-name $VM_NAME \
  --item-name $VM_NAME \
  --backup-management-type AzureIaasVM
```

## Interview Questions

### Q1: What is the difference between stopping and deallocating a VM?
**Answer:**
- **Stop (OS-level)**: VM is stopped but Azure still has compute resources allocated. You're still billed for compute.
- **Deallocate**: Azure releases the compute resources. You're only billed for storage (OS disk, data disks). The public IP may change unless it's static.
- **Best practice**: Always deallocate VMs when not needed to save costs.

### Q2: What are Availability Zones vs Availability Sets?
**Answer:**
- **Availability Zones**: Physically separate datacenters within a region. Protects against datacenter failure. SLA 99.99%. Recommended for new deployments.
- **Availability Sets**: Logical grouping within a datacenter using fault domains (separate racks) and update domains. SLA 99.95%. Legacy approach.
- **Key difference**: AZs protect against datacenter failure; AS protects against rack/maintenance failures.

### Q3: What is a VM Scale Set and when would you use it?
**Answer:**
VMSS creates and manages a group of identical, load-balanced VMs. Use when:
- Need auto-scaling based on demand
- Running stateless workloads (web servers, API servers)
- Need to handle variable traffic
- Want to reduce costs by scaling down during off-peak hours

### Q4: What disk type should you use for a production SQL Server database?
**Answer:**
- **Ultra Disk** for highest performance requirements (< 1ms latency, high IOPS)
- **Premium SSD** for most production databases (good balance of performance/cost)
- Set disk caching to **None** for data disks on databases (prevents data corruption)
- Use **Write Accelerator** for M-series VMs with Premium SSD for log files

### Q5: How do you secure a VM in Azure?
**Answer:**
1. Use SSH keys (not passwords) for Linux; disable password auth
2. Place VM in a VNet with NSG — deny all inbound by default
3. Use Azure Bastion for secure RDP/SSH (no public IP needed)
4. Enable Azure Defender for Servers
5. Keep OS patched (Azure Update Manager)
6. Use Managed Identity instead of credentials in apps
7. Enable disk encryption (Azure Disk Encryption or SSE with CMK)
8. Enable boot diagnostics and monitoring
