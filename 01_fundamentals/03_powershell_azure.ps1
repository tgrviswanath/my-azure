# Azure PowerShell — Essential Commands Reference
# Install: Install-Module -Name Az -AllowClobber -Scope CurrentUser
# Connect: Connect-AzAccount

#Requires -Modules Az

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Authentication ─────────────────────────────────────────────────────────────
Connect-AzAccount                                          # Interactive login
Connect-AzAccount -ServicePrincipal `
    -ApplicationId $AppId `
    -TenantId $TenantId `
    -CertificateThumbprint $Thumbprint                     # Service principal

Get-AzContext                                              # Current subscription
Get-AzSubscription                                         # List all subscriptions
Set-AzContext -SubscriptionId "SUBSCRIPTION_ID"           # Switch subscription

# ── Resource Groups ────────────────────────────────────────────────────────────
$RG       = "rg-demo-dev-eastus"
$Location = "eastus"

New-AzResourceGroup -Name $RG -Location $Location -Tag @{
    Environment = "Dev"
    Project     = "Demo"
    Owner       = "TeamA"
}

Get-AzResourceGroup | Format-Table ResourceGroupName, Location, ProvisioningState
Remove-AzResourceGroup -Name $RG -Force -AsJob

# ── Virtual Machines ───────────────────────────────────────────────────────────
$VMName   = "vm-web-dev-001"
$VMSize   = "Standard_B2s"
$Image    = "Ubuntu2204"
$AdminUser = "azureuser"

# Create VM with all components
$Credential = Get-Credential -UserName $AdminUser -Message "Enter VM password"

$VMConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize |
    Set-AzVMOperatingSystem -Linux -ComputerName $VMName -Credential $Credential |
    Set-AzVMSourceImage -PublisherName "Canonical" -Offer "0001-com-ubuntu-server-jammy" `
        -Skus "22_04-lts-gen2" -Version "latest" |
    Add-AzVMNetworkInterface -Id $NIC.Id

New-AzVM -ResourceGroupName $RG -Location $Location -VM $VMConfig -Tag @{Role="WebServer"}

# VM operations
Start-AzVM    -ResourceGroupName $RG -Name $VMName
Stop-AzVM     -ResourceGroupName $RG -Name $VMName -Force
Restart-AzVM  -ResourceGroupName $RG -Name $VMName
Remove-AzVM   -ResourceGroupName $RG -Name $VMName -Force

# Get VM status
Get-AzVM -ResourceGroupName $RG -Name $VMName -Status |
    Select-Object -ExpandProperty Statuses |
    Format-Table Code, DisplayStatus

# ── Storage ────────────────────────────────────────────────────────────────────
$StorageName = "stdemoprod$(Get-Random -Maximum 9999)"

$StorageAccount = New-AzStorageAccount `
    -ResourceGroupName $RG `
    -Name $StorageName `
    -Location $Location `
    -SkuName Standard_ZRS `
    -Kind StorageV2 `
    -AccessTier Hot `
    -EnableHttpsTrafficOnly $true `
    -MinimumTlsVersion TLS1_2 `
    -AllowBlobPublicAccess $false

$Context = $StorageAccount.Context

# Create container
New-AzStorageContainer -Name "uploads" -Context $Context -Permission Off

# Upload blob
Set-AzStorageBlobContent `
    -Container "uploads" `
    -File ".\test.txt" `
    -Blob "test.txt" `
    -Context $Context `
    -StandardBlobTier Hot

# List blobs
Get-AzStorageBlob -Container "uploads" -Context $Context |
    Select-Object Name, Length, LastModified | Format-Table

# Generate SAS token
$SasToken = New-AzStorageBlobSASToken `
    -Container "uploads" `
    -Blob "test.txt" `
    -Permission "r" `
    -ExpiryTime (Get-Date).AddHours(1) `
    -Context $Context `
    -FullUri

Write-Host "SAS URL: $SasToken"

# ── App Service ────────────────────────────────────────────────────────────────
$AppPlan = "asp-webapp-dev"
$AppName = "app-webapp-dev-$(Get-Random -Maximum 9999)"

New-AzAppServicePlan `
    -ResourceGroupName $RG `
    -Name $AppPlan `
    -Location $Location `
    -Tier "Basic" `
    -NumberofWorkers 1 `
    -WorkerSize "Small" `
    -Linux

New-AzWebApp `
    -ResourceGroupName $RG `
    -Name $AppName `
    -Location $Location `
    -AppServicePlan $AppPlan

# Set app settings
$AppSettings = @{
    "NODE_ENV"    = "production"
    "PORT"        = "8080"
    "LOG_LEVEL"   = "info"
}
Set-AzWebApp -ResourceGroupName $RG -Name $AppName -AppSettings $AppSettings

# Enable managed identity
Set-AzWebApp -ResourceGroupName $RG -Name $AppName -AssignIdentity $true

# ── Key Vault ──────────────────────────────────────────────────────────────────
$KVName = "kv-demo-dev-$(Get-Random -Maximum 9999)"

New-AzKeyVault `
    -Name $KVName `
    -ResourceGroupName $RG `
    -Location $Location `
    -Sku Standard `
    -EnableRbacAuthorization $true `
    -SoftDeleteRetentionInDays 7

# Add secret
$SecretValue = ConvertTo-SecureString "SuperSecretPassword123!" -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $KVName -Name "DatabasePassword" -SecretValue $SecretValue

# Get secret
$Secret = Get-AzKeyVaultSecret -VaultName $KVName -Name "DatabasePassword" -AsPlainText
Write-Host "Secret value: $Secret"

# ── Networking ─────────────────────────────────────────────────────────────────
$VNetName   = "vnet-app-dev"
$SubnetWeb  = "snet-web"
$SubnetDB   = "snet-db"

# Create VNet with subnets
$WebSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name $SubnetWeb `
    -AddressPrefix "10.0.1.0/24"

$DBSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name $SubnetDB `
    -AddressPrefix "10.0.2.0/24"

$VNet = New-AzVirtualNetwork `
    -Name $VNetName `
    -ResourceGroupName $RG `
    -Location $Location `
    -AddressPrefix "10.0.0.0/16" `
    -Subnet @($WebSubnet, $DBSubnet)

# Create NSG
$NSGName = "nsg-web-dev"
$AllowHTTPS = New-AzNetworkSecurityRuleConfig `
    -Name "AllowHTTPS" `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 100 `
    -SourceAddressPrefix Internet `
    -SourcePortRange "*" `
    -DestinationAddressPrefix "*" `
    -DestinationPortRange 443 `
    -Access Allow

$DenyAll = New-AzNetworkSecurityRuleConfig `
    -Name "DenyAllInbound" `
    -Protocol "*" `
    -Direction Inbound `
    -Priority 4096 `
    -SourceAddressPrefix "*" `
    -SourcePortRange "*" `
    -DestinationAddressPrefix "*" `
    -DestinationPortRange "*" `
    -Access Deny

$NSG = New-AzNetworkSecurityGroup `
    -Name $NSGName `
    -ResourceGroupName $RG `
    -Location $Location `
    -SecurityRules @($AllowHTTPS, $DenyAll)

# ── Azure SQL ──────────────────────────────────────────────────────────────────
$SQLServerName = "sql-demo-dev-$(Get-Random -Maximum 9999)"
$SQLAdminCred  = Get-Credential -UserName "sqladmin" -Message "SQL admin password"

New-AzSqlServer `
    -ResourceGroupName $RG `
    -ServerName $SQLServerName `
    -Location $Location `
    -SqlAdministratorCredentials $SQLAdminCred `
    -MinimalTlsVersion "1.2" `
    -PublicNetworkAccess "Disabled"

New-AzSqlDatabase `
    -ResourceGroupName $RG `
    -ServerName $SQLServerName `
    -DatabaseName "myapp-db" `
    -Edition "GeneralPurpose" `
    -VCore 2 `
    -ComputeGeneration "Gen5" `
    -ZoneRedundant $false

# ── Monitoring ─────────────────────────────────────────────────────────────────
$LAWName = "law-demo-dev"

New-AzOperationalInsightsWorkspace `
    -ResourceGroupName $RG `
    -Name $LAWName `
    -Location $Location `
    -Sku PerGB2018 `
    -RetentionInDays 30

# Create metric alert
$Condition = New-AzMetricAlertRuleV2Criteria `
    -MetricName "Percentage CPU" `
    -TimeAggregation Average `
    -Operator GreaterThan `
    -Threshold 80

Add-AzMetricAlertRuleV2 `
    -ResourceGroupName $RG `
    -Name "HighCPU-$VMName" `
    -WindowSize ([TimeSpan]::FromMinutes(5)) `
    -Frequency ([TimeSpan]::FromMinutes(1)) `
    -TargetResourceId $VM.Id `
    -Condition $Condition `
    -Severity 2 `
    -Description "CPU > 80% for 5 minutes"

# ── Useful Functions ───────────────────────────────────────────────────────────

function Get-AzResourceCosts {
    param(
        [string]$ResourceGroupName,
        [int]$DaysBack = 30
    )
    $StartDate = (Get-Date).AddDays(-$DaysBack).ToString("yyyy-MM-dd")
    $EndDate   = (Get-Date).ToString("yyyy-MM-dd")

    Get-AzConsumptionUsageDetail `
        -StartDate $StartDate `
        -EndDate $EndDate `
        -ResourceGroup $ResourceGroupName |
        Group-Object -Property InstanceName |
        Select-Object Name, @{N="Cost";E={($_.Group | Measure-Object -Property PretaxCost -Sum).Sum}} |
        Sort-Object Cost -Descending
}

function Set-AzVMAutoShutdown {
    param(
        [string]$ResourceGroupName,
        [string]$VMName,
        [string]$ShutdownTime = "1900",
        [string]$TimeZone = "Eastern Standard Time",
        [string]$Email
    )
    $ScheduledShutdownResourceId = "/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/$ResourceGroupName/providers/microsoft.devtestlab/schedules/shutdown-computevm-$VMName"

    $Properties = @{
        status           = "Enabled"
        taskType         = "ComputeVmShutdownTask"
        dailyRecurrence  = @{ time = $ShutdownTime }
        timeZoneId       = $TimeZone
        targetResourceId = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName).Id
        notificationSettings = @{
            status        = if ($Email) { "Enabled" } else { "Disabled" }
            timeInMinutes = 30
            emailRecipient = $Email
        }
    }

    New-AzResource `
        -ResourceId $ScheduledShutdownResourceId `
        -Location (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName).Location `
        -Properties $Properties `
        -Force
}

function Get-AzOrphanedDisks {
    param([string]$ResourceGroupName)
    Get-AzDisk -ResourceGroupName $ResourceGroupName |
        Where-Object { $null -eq $_.ManagedBy } |
        Select-Object Name, DiskSizeGB, Location, TimeCreated |
        Format-Table
}

function Get-AzUnusedPublicIPs {
    param([string]$ResourceGroupName)
    Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName |
        Where-Object { $null -eq $_.IpConfiguration } |
        Select-Object Name, Location, PublicIpAllocationMethod |
        Format-Table
}

# ── Cleanup ────────────────────────────────────────────────────────────────────
# Remove-AzResourceGroup -Name $RG -Force -AsJob
Write-Host "Azure PowerShell reference complete!"
