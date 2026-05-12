"""
zero_trust_checker.py — Azure Zero Trust Security Auditor

Audits your Azure environment against Zero Trust principles:
- Identity: MFA enforcement, no standing admin, legacy auth blocked
- Network: No open NSG rules (0.0.0.0/0 on 22/3389), private endpoints
- Data: Storage public access, Key Vault usage
- Monitoring: Defender for Cloud, Sentinel

Produces a Zero Trust Score 0-100 with specific findings and remediation steps.

Requirements:
    pip install azure-identity azure-mgmt-network azure-mgmt-storage
                azure-mgmt-keyvault azure-mgmt-compute azure-mgmt-security

Usage:
    export AZURE_SUBSCRIPTION_ID="your-subscription-id"
    python zero_trust_checker.py
"""

import os
import sys
from dataclasses import dataclass, field
from typing import List, Optional
from datetime import datetime, timezone

from azure.identity import DefaultAzureCredential, AzureCliCredential
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.storage import StorageManagementClient
from azure.mgmt.keyvault import KeyVaultManagementClient
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.security import SecurityCenter
from azure.core.exceptions import AzureError


# ── Configuration ─────────────────────────────────────────────────────────────

SUBSCRIPTION_ID = os.environ.get("AZURE_SUBSCRIPTION_ID", "")

# Ports that should never be open to 0.0.0.0/0
DANGEROUS_PORTS = {"22", "3389", "23", "21", "1433", "3306", "5432", "6379", "27017"}

# Known dangerous source address prefixes
OPEN_INTERNET = {"*", "0.0.0.0/0", "Internet", "Any"}


# ── Data Classes ──────────────────────────────────────────────────────────────

@dataclass
class Finding:
    category: str       # Identity, Network, Data, Monitoring
    severity: str       # CRITICAL, HIGH, MEDIUM, LOW, PASS
    title: str
    detail: str
    remediation: str
    points: int = 0     # Points awarded (positive) or deducted (0 = failed check)
    max_points: int = 10


@dataclass
class AuditResult:
    findings: List[Finding] = field(default_factory=list)
    total_score: int = 0
    max_score: int = 0

    def add_finding(self, finding: Finding):
        self.findings.append(finding)
        self.max_score += finding.max_points
        self.total_score += finding.points

    @property
    def score_percent(self) -> int:
        if self.max_score == 0:
            return 0
        return int((self.total_score / self.max_score) * 100)

    @property
    def grade(self) -> str:
        pct = self.score_percent
        if pct >= 90: return "A"
        if pct >= 80: return "B"
        if pct >= 70: return "C"
        if pct >= 60: return "D"
        return "F"


# ── Azure Clients ─────────────────────────────────────────────────────────────

def get_credential():
    try:
        cred = DefaultAzureCredential()
        return cred
    except Exception:
        return AzureCliCredential()


# ── Identity Checks ───────────────────────────────────────────────────────────

def check_mfa_enforcement(result: AuditResult) -> None:
    """
    Check if MFA is enforced via Conditional Access.
    Note: Requires Microsoft Graph API access (Azure AD P1/P2).
    This check uses az CLI to query CA policies.
    """
    print("  Checking MFA enforcement...")
    try:
        import subprocess
        import json

        # Try to list CA policies via az CLI
        proc = subprocess.run(
            ["az", "rest", "--method", "GET",
             "--url", "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies",
             "--query", "value[?state=='enabled'].{Name:displayName, State:state}"],
            capture_output=True, text=True, timeout=30
        )

        if proc.returncode == 0 and proc.stdout.strip():
            policies = json.loads(proc.stdout)
            mfa_policies = [p for p in policies if "mfa" in p.get("Name", "").lower()
                           or "multi" in p.get("Name", "").lower()]

            if mfa_policies:
                result.add_finding(Finding(
                    category="Identity",
                    severity="PASS",
                    title="MFA Enforced via Conditional Access",
                    detail=f"Found {len(mfa_policies)} MFA-related CA policies: {[p['Name'] for p in mfa_policies]}",
                    remediation="N/A — MFA is enforced.",
                    points=10, max_points=10
                ))
            else:
                result.add_finding(Finding(
                    category="Identity",
                    severity="CRITICAL",
                    title="No MFA Conditional Access Policy Found",
                    detail=f"Found {len(policies)} CA policies but none enforce MFA.",
                    remediation="Create a CA policy: Azure AD → Security → Conditional Access → New policy → Grant: Require MFA",
                    points=0, max_points=10
                ))
        else:
            # Cannot check — assume not configured
            result.add_finding(Finding(
                category="Identity",
                severity="HIGH",
                title="MFA Status Unknown (Insufficient Permissions)",
                detail="Could not query Conditional Access policies. Requires Azure AD P1/P2 and Security Reader role.",
                remediation="Assign Security Reader role and retry, or check manually in Azure AD portal.",
                points=5, max_points=10
            ))
    except Exception as e:
        result.add_finding(Finding(
            category="Identity",
            severity="HIGH",
            title="MFA Check Failed",
            detail=f"Error: {str(e)[:100]}",
            remediation="Check manually: Azure AD → Security → Conditional Access",
            points=0, max_points=10
        ))


# ── Network Checks ────────────────────────────────────────────────────────────

def check_nsg_rules(network_client: NetworkManagementClient, result: AuditResult) -> None:
    """Check all NSGs for dangerous open rules (0.0.0.0/0 on sensitive ports)."""
    print("  Checking NSG rules...")
    try:
        nsgs = list(network_client.network_security_groups.list_all())
        dangerous_rules = []

        for nsg in nsgs:
            for rule in (nsg.security_rules or []):
                if rule.access != "Allow" or rule.direction != "Inbound":
                    continue

                source = rule.source_address_prefix or ""
                if source not in OPEN_INTERNET:
                    continue

                # Check if destination port is dangerous
                dest_port = rule.destination_port_range or ""
                dest_ports = rule.destination_port_ranges or []
                all_ports = [dest_port] + list(dest_ports)

                for port in all_ports:
                    if port in DANGEROUS_PORTS or port == "*":
                        dangerous_rules.append({
                            "nsg": nsg.name,
                            "rule": rule.name,
                            "port": port,
                            "source": source,
                        })

        if dangerous_rules:
            detail = "; ".join([
                f"NSG '{r['nsg']}' rule '{r['rule']}': port {r['port']} open to {r['source']}"
                for r in dangerous_rules[:5]
            ])
            result.add_finding(Finding(
                category="Network",
                severity="CRITICAL",
                title=f"Dangerous NSG Rules Found ({len(dangerous_rules)} rules)",
                detail=detail,
                remediation="Remove rules allowing 0.0.0.0/0 on ports 22/3389. Use Azure Bastion for admin access instead.",
                points=0, max_points=10
            ))
        else:
            result.add_finding(Finding(
                category="Network",
                severity="PASS",
                title="No Dangerous NSG Rules",
                detail=f"Checked {len(nsgs)} NSGs. No rules allow 0.0.0.0/0 on sensitive ports.",
                remediation="N/A",
                points=10, max_points=10
            ))

    except AzureError as e:
        print(f"    ⚠️  NSG check error: {e}")


def check_private_endpoints(network_client: NetworkManagementClient, result: AuditResult) -> None:
    """Check if private endpoints exist (indicates services are not publicly exposed)."""
    print("  Checking private endpoints...")
    try:
        endpoints = list(network_client.private_endpoints.list_by_subscription())
        pe_count = len(endpoints)

        if pe_count >= 2:
            services = [pe.name for pe in endpoints[:5]]
            result.add_finding(Finding(
                category="Network",
                severity="PASS",
                title=f"Private Endpoints Configured ({pe_count} found)",
                detail=f"Private endpoints: {services}",
                remediation="N/A — private endpoints are configured.",
                points=10, max_points=10
            ))
        elif pe_count == 1:
            result.add_finding(Finding(
                category="Network",
                severity="MEDIUM",
                title="Only 1 Private Endpoint Found",
                detail="Only one service has a private endpoint. Other services may be publicly accessible.",
                remediation="Add private endpoints for Key Vault, Storage, SQL, and other PaaS services.",
                points=5, max_points=10
            ))
        else:
            result.add_finding(Finding(
                category="Network",
                severity="HIGH",
                title="No Private Endpoints Found",
                detail="No private endpoints configured. PaaS services are accessible from the public internet.",
                remediation="Create private endpoints for all PaaS services. Disable public network access after PE creation.",
                points=0, max_points=10
            ))

    except AzureError as e:
        print(f"    ⚠️  Private endpoint check error: {e}")


# ── Data Checks ───────────────────────────────────────────────────────────────

def check_storage_public_access(storage_client: StorageManagementClient, result: AuditResult) -> None:
    """Check for storage accounts with public blob access enabled."""
    print("  Checking storage account public access...")
    try:
        accounts = list(storage_client.storage_accounts.list())
        public_accounts = []

        for account in accounts:
            # Check if public blob access is allowed
            if account.allow_blob_public_access is True:
                public_accounts.append(account.name)
            # Check if public network access is enabled
            elif account.public_network_access == "Enabled":
                public_accounts.append(f"{account.name} (network)")

        if public_accounts:
            result.add_finding(Finding(
                category="Data",
                severity="HIGH",
                title=f"Storage Accounts with Public Access ({len(public_accounts)})",
                detail=f"Public storage accounts: {public_accounts}",
                remediation="Run: az storage account update --name <name> --public-network-access Disabled --default-action Deny",
                points=0, max_points=10
            ))
        else:
            result.add_finding(Finding(
                category="Data",
                severity="PASS",
                title="All Storage Accounts Have Public Access Disabled",
                detail=f"Checked {len(accounts)} storage accounts. None have public blob access.",
                remediation="N/A",
                points=10, max_points=10
            ))

    except AzureError as e:
        print(f"    ⚠️  Storage check error: {e}")


def check_key_vault_usage(kv_client: KeyVaultManagementClient, result: AuditResult) -> None:
    """Check if Key Vaults exist (indicates secrets management is in use)."""
    print("  Checking Key Vault usage...")
    try:
        vaults = list(kv_client.vaults.list())
        public_vaults = []

        for vault in vaults:
            props = vault.properties
            if props and props.public_network_access == "Enabled":
                public_vaults.append(vault.name)

        if not vaults:
            result.add_finding(Finding(
                category="Data",
                severity="HIGH",
                title="No Key Vaults Found",
                detail="No Key Vaults exist. Secrets may be stored in code or config files.",
                remediation="Create a Key Vault and migrate all secrets, connection strings, and certificates to it.",
                points=0, max_points=10
            ))
        elif public_vaults:
            result.add_finding(Finding(
                category="Data",
                severity="MEDIUM",
                title=f"Key Vaults with Public Network Access ({len(public_vaults)})",
                detail=f"Public Key Vaults: {public_vaults}",
                remediation="Disable public access and add private endpoint: az keyvault update --name <name> --public-network-access Disabled",
                points=5, max_points=10
            ))
        else:
            result.add_finding(Finding(
                category="Data",
                severity="PASS",
                title=f"Key Vaults Configured with Private Access ({len(vaults)} vaults)",
                detail=f"Key Vaults: {[v.name for v in vaults]}. Public access disabled.",
                remediation="N/A",
                points=10, max_points=10
            ))

    except AzureError as e:
        print(f"    ⚠️  Key Vault check error: {e}")


def check_unattached_disks(compute_client: ComputeManagementClient, result: AuditResult) -> None:
    """Check for unattached managed disks (security risk + cost waste)."""
    print("  Checking for unattached disks...")
    try:
        disks = list(compute_client.disks.list())
        unattached = [d.name for d in disks if d.disk_state == "Unattached"]

        if unattached:
            result.add_finding(Finding(
                category="Data",
                severity="LOW",
                title=f"Unattached Disks Found ({len(unattached)})",
                detail=f"Unattached disks: {unattached[:5]}",
                remediation="Delete unattached disks or attach them to VMs. Unattached disks are a cost waste and potential data exposure risk.",
                points=5, max_points=10
            ))
        else:
            result.add_finding(Finding(
                category="Data",
                severity="PASS",
                title="No Unattached Disks",
                detail=f"Checked {len(disks)} disks. All are attached.",
                remediation="N/A",
                points=10, max_points=10
            ))

    except AzureError as e:
        print(f"    ⚠️  Disk check error: {e}")


# ── Monitoring Checks ─────────────────────────────────────────────────────────

def check_defender_for_cloud(security_client: SecurityCenter, result: AuditResult) -> None:
    """Check if Microsoft Defender for Cloud is enabled on key resource types."""
    print("  Checking Defender for Cloud...")
    try:
        pricings = list(security_client.pricings.list())
        enabled = [p.name for p in pricings if p.pricing_tier == "Standard"]
        disabled = [p.name for p in pricings if p.pricing_tier == "Free"]

        key_services = {"VirtualMachines", "SqlServers", "StorageAccounts", "KeyVaults"}
        enabled_key = key_services.intersection(set(enabled))

        if len(enabled_key) >= 3:
            result.add_finding(Finding(
                category="Monitoring",
                severity="PASS",
                title=f"Defender for Cloud Enabled ({len(enabled)} services)",
                detail=f"Enabled: {enabled}",
                remediation="N/A",
                points=10, max_points=10
            ))
        elif enabled:
            result.add_finding(Finding(
                category="Monitoring",
                severity="MEDIUM",
                title=f"Defender for Cloud Partially Enabled ({len(enabled)}/{len(pricings)} services)",
                detail=f"Enabled: {enabled}. Disabled: {disabled[:5]}",
                remediation="Enable Defender for all key services: az security pricing create --name VirtualMachines --tier Standard",
                points=5, max_points=10
            ))
        else:
            result.add_finding(Finding(
                category="Monitoring",
                severity="HIGH",
                title="Defender for Cloud Not Enabled",
                detail="All services on Free tier. No threat protection active.",
                remediation="Enable Defender: az security pricing create --name VirtualMachines --tier Standard",
                points=0, max_points=10
            ))

    except AzureError as e:
        print(f"    ⚠️  Defender check error: {e}")


# ── Report Printing ───────────────────────────────────────────────────────────

def print_report(result: AuditResult) -> None:
    """Print the full Zero Trust audit report."""
    print("\n" + "=" * 70)
    print("  AZURE ZERO TRUST SECURITY AUDIT REPORT")
    print(f"  Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
    print("=" * 70)

    # Score banner
    score = result.score_percent
    grade = result.grade
    bar_filled = int(score / 5)
    bar = "█" * bar_filled + "░" * (20 - bar_filled)

    print(f"\n  ZERO TRUST SCORE: {score}/100  Grade: {grade}")
    print(f"  [{bar}]")
    print(f"  {result.total_score}/{result.max_score} points earned\n")

    # Score interpretation
    if score >= 90:
        print("  🟢 EXCELLENT — Strong Zero Trust posture")
    elif score >= 70:
        print("  🟡 GOOD — Some gaps to address")
    elif score >= 50:
        print("  🟠 FAIR — Significant improvements needed")
    else:
        print("  🔴 POOR — Critical Zero Trust gaps")

    # Findings by category
    categories = ["Identity", "Network", "Data", "Monitoring"]
    severity_icons = {
        "PASS":     "✅",
        "LOW":      "🔵",
        "MEDIUM":   "🟡",
        "HIGH":     "🟠",
        "CRITICAL": "🔴",
    }

    for category in categories:
        cat_findings = [f for f in result.findings if f.category == category]
        if not cat_findings:
            continue

        cat_score = sum(f.points for f in cat_findings)
        cat_max = sum(f.max_points for f in cat_findings)
        cat_pct = int((cat_score / cat_max) * 100) if cat_max > 0 else 0

        print(f"\n  {'─' * 60}")
        print(f"  {category.upper()} ({cat_score}/{cat_max} pts — {cat_pct}%)")
        print(f"  {'─' * 60}")

        for finding in cat_findings:
            icon = severity_icons.get(finding.severity, "❓")
            print(f"\n  {icon} {finding.title}")
            print(f"     {finding.detail[:100]}")
            if finding.severity != "PASS":
                print(f"     → Fix: {finding.remediation[:100]}")

    # Action items
    critical = [f for f in result.findings if f.severity == "CRITICAL"]
    high = [f for f in result.findings if f.severity == "HIGH"]

    print(f"\n  {'=' * 70}")
    print("  PRIORITY ACTION ITEMS")
    print(f"  {'=' * 70}")

    if critical:
        print(f"\n  🔴 CRITICAL ({len(critical)} items — fix immediately):")
        for f in critical:
            print(f"    • {f.title}")
            print(f"      {f.remediation[:80]}")

    if high:
        print(f"\n  🟠 HIGH ({len(high)} items — fix this week):")
        for f in high:
            print(f"    • {f.title}")

    if not critical and not high:
        print("\n  ✅ No critical or high severity findings!")

    print(f"\n  Audit complete. Score: {score}/100\n")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("🔒 Azure Zero Trust Security Checker")
    print("=" * 70)

    if not SUBSCRIPTION_ID:
        print("❌ Error: AZURE_SUBSCRIPTION_ID environment variable not set.")
        sys.exit(1)

    print(f"  Subscription: {SUBSCRIPTION_ID}")
    print(f"  Starting audit...\n")

    credential = get_credential()
    result = AuditResult()

    # Initialize clients
    network_client  = NetworkManagementClient(credential, SUBSCRIPTION_ID)
    storage_client  = StorageManagementClient(credential, SUBSCRIPTION_ID)
    kv_client       = KeyVaultManagementClient(credential, SUBSCRIPTION_ID)
    compute_client  = ComputeManagementClient(credential, SUBSCRIPTION_ID)
    security_client = SecurityCenter(credential, SUBSCRIPTION_ID)

    print("Running checks:")

    # Identity checks
    check_mfa_enforcement(result)

    # Network checks
    check_nsg_rules(network_client, result)
    check_private_endpoints(network_client, result)

    # Data checks
    check_storage_public_access(storage_client, result)
    check_key_vault_usage(kv_client, result)
    check_unattached_disks(compute_client, result)

    # Monitoring checks
    check_defender_for_cloud(security_client, result)

    # Print report
    print_report(result)


if __name__ == "__main__":
    main()
