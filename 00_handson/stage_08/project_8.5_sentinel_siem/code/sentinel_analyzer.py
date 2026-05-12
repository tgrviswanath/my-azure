"""
sentinel_analyzer.py — Microsoft Sentinel Incident Analyzer

Uses azure-mgmt-securityinsight to:
- List incidents by severity
- Get incident details and entities
- List active analytics rules
- Print a formatted incident report

Requirements:
    pip install azure-identity azure-mgmt-securityinsight

Usage:
    export AZURE_SUBSCRIPTION_ID="your-subscription-id"
    export SENTINEL_RESOURCE_GROUP="rg-sentinel-lab"
    export SENTINEL_WORKSPACE="law-sentinel-lab"
    python sentinel_analyzer.py
"""

import os
import sys
from datetime import datetime, timezone
from typing import Optional

from azure.identity import DefaultAzureCredential, AzureCliCredential
from azure.mgmt.securityinsight import SecurityInsights
from azure.mgmt.securityinsight.models import (
    IncidentSeverityEnum,
    IncidentStatusEnum,
)
from azure.core.exceptions import AzureError


# ── Configuration ────────────────────────────────────────────────────────────

SUBSCRIPTION_ID = os.environ.get("AZURE_SUBSCRIPTION_ID", "")
RESOURCE_GROUP  = os.environ.get("SENTINEL_RESOURCE_GROUP", "rg-sentinel-lab")
WORKSPACE_NAME  = os.environ.get("SENTINEL_WORKSPACE", "law-sentinel-lab")

SEVERITY_ORDER = {
    "High":          1,
    "Medium":        2,
    "Low":           3,
    "Informational": 4,
}

SEVERITY_COLORS = {
    "High":          "🔴",
    "Medium":        "🟡",
    "Low":           "🔵",
    "Informational": "⚪",
}


# ── Sentinel Client ───────────────────────────────────────────────────────────

def get_sentinel_client(subscription_id: str) -> SecurityInsights:
    """Create authenticated Sentinel client using DefaultAzureCredential."""
    try:
        credential = DefaultAzureCredential()
        return SecurityInsights(credential, subscription_id)
    except Exception:
        # Fallback to Azure CLI credential
        credential = AzureCliCredential()
        return SecurityInsights(credential, subscription_id)


# ── Incident Functions ────────────────────────────────────────────────────────

def list_incidents(
    client: SecurityInsights,
    resource_group: str,
    workspace: str,
    status_filter: Optional[str] = None,
    severity_filter: Optional[str] = None,
    top: int = 50,
) -> list:
    """
    List Sentinel incidents with optional filters.

    Args:
        client: SecurityInsights client
        resource_group: Resource group name
        workspace: Log Analytics workspace name
        status_filter: Filter by status (New, Active, Closed)
        severity_filter: Filter by severity (High, Medium, Low, Informational)
        top: Maximum number of incidents to return

    Returns:
        List of incident objects sorted by severity then creation time
    """
    filter_parts = []
    if status_filter:
        filter_parts.append(f"properties/status eq '{status_filter}'")
    if severity_filter:
        filter_parts.append(f"properties/severity eq '{severity_filter}'")

    odata_filter = " and ".join(filter_parts) if filter_parts else None

    try:
        incidents = list(
            client.incidents.list(
                resource_group_name=resource_group,
                workspace_name=workspace,
                filter=odata_filter,
                top=top,
                orderby="properties/createdTimeUtc desc",
            )
        )
        # Sort by severity priority
        incidents.sort(
            key=lambda i: (
                SEVERITY_ORDER.get(i.severity, 99),
                -(i.created_time_utc.timestamp() if i.created_time_utc else 0),
            )
        )
        return incidents
    except AzureError as e:
        print(f"  ⚠️  Error listing incidents: {e}")
        return []


def get_incident_details(
    client: SecurityInsights,
    resource_group: str,
    workspace: str,
    incident_id: str,
) -> dict:
    """
    Get detailed information about a specific incident including entities.

    Returns:
        Dict with incident details and entity list
    """
    try:
        incident = client.incidents.get(
            resource_group_name=resource_group,
            workspace_name=workspace,
            incident_id=incident_id,
        )

        # Get entities associated with the incident
        entities_response = client.incidents.list_entities(
            resource_group_name=resource_group,
            workspace_name=workspace,
            incident_id=incident_id,
        )

        entities = []
        for entity in (entities_response.entities or []):
            entity_info = {
                "kind": entity.kind,
                "id": entity.id,
            }
            # Extract friendly name based on entity type
            if hasattr(entity, "address"):
                entity_info["value"] = entity.address  # IP entity
            elif hasattr(entity, "user_principal_name"):
                entity_info["value"] = entity.user_principal_name  # Account entity
            elif hasattr(entity, "host_name"):
                entity_info["value"] = entity.host_name  # Host entity
            elif hasattr(entity, "url"):
                entity_info["value"] = entity.url  # URL entity
            else:
                entity_info["value"] = str(entity.id)

            entities.append(entity_info)

        return {
            "incident": incident,
            "entities": entities,
        }

    except AzureError as e:
        print(f"  ⚠️  Error getting incident {incident_id}: {e}")
        return {}


def list_analytics_rules(
    client: SecurityInsights,
    resource_group: str,
    workspace: str,
) -> list:
    """
    List all active analytics rules in Sentinel.

    Returns:
        List of analytics rule objects
    """
    try:
        rules = list(
            client.alert_rules.list(
                resource_group_name=resource_group,
                workspace_name=workspace,
            )
        )
        return rules
    except AzureError as e:
        print(f"  ⚠️  Error listing analytics rules: {e}")
        return []


# ── Report Formatting ─────────────────────────────────────────────────────────

def format_time_ago(dt: Optional[datetime]) -> str:
    """Format datetime as human-readable 'X hours ago'."""
    if not dt:
        return "Unknown"
    now = datetime.now(timezone.utc)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    diff = now - dt
    seconds = int(diff.total_seconds())
    if seconds < 60:
        return f"{seconds}s ago"
    elif seconds < 3600:
        return f"{seconds // 60}m ago"
    elif seconds < 86400:
        return f"{seconds // 3600}h ago"
    else:
        return f"{seconds // 86400}d ago"


def print_incident_report(incidents: list, workspace: str) -> None:
    """Print a formatted incident report to stdout."""
    print("\n" + "=" * 70)
    print(f"  MICROSOFT SENTINEL — INCIDENT REPORT")
    print(f"  Workspace: {workspace}")
    print(f"  Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
    print("=" * 70)

    if not incidents:
        print("\n  ✅ No incidents found matching the filter criteria.\n")
        return

    # Summary by severity
    severity_counts = {}
    status_counts = {}
    for inc in incidents:
        sev = inc.severity or "Unknown"
        sta = inc.status or "Unknown"
        severity_counts[sev] = severity_counts.get(sev, 0) + 1
        status_counts[sta] = status_counts.get(sta, 0) + 1

    print(f"\n  📊 SUMMARY: {len(incidents)} total incidents")
    print(f"  {'─' * 40}")
    for sev in ["High", "Medium", "Low", "Informational"]:
        count = severity_counts.get(sev, 0)
        if count > 0:
            icon = SEVERITY_COLORS.get(sev, "⚪")
            print(f"  {icon} {sev:<15} {count:>3} incidents")

    print(f"\n  Status breakdown:")
    for status, count in sorted(status_counts.items()):
        print(f"    • {status:<12} {count:>3}")

    # Incident details
    print(f"\n  {'─' * 70}")
    print(f"  INCIDENT DETAILS")
    print(f"  {'─' * 70}")

    for i, incident in enumerate(incidents[:20], 1):  # Show top 20
        sev_icon = SEVERITY_COLORS.get(incident.severity, "⚪")
        status = incident.status or "Unknown"
        title = incident.title or "Untitled"
        incident_number = incident.incident_number or "N/A"
        created = format_time_ago(incident.created_time_utc)
        updated = format_time_ago(incident.last_modified_time_utc)

        print(f"\n  [{i:02d}] {sev_icon} #{incident_number} — {title}")
        print(f"       Severity : {incident.severity}")
        print(f"       Status   : {status}")
        print(f"       Created  : {created}")
        print(f"       Updated  : {updated}")

        if incident.description:
            desc = incident.description[:100] + "..." if len(incident.description) > 100 else incident.description
            print(f"       Desc     : {desc}")

        if incident.alerts_count:
            print(f"       Alerts   : {incident.alerts_count}")

        if incident.owner and incident.owner.assigned_to:
            print(f"       Owner    : {incident.owner.assigned_to}")

        # Tactics
        if incident.additional_data and incident.additional_data.tactics:
            tactics = ", ".join(incident.additional_data.tactics)
            print(f"       Tactics  : {tactics}")


def print_analytics_rules_report(rules: list) -> None:
    """Print a formatted analytics rules report."""
    print(f"\n  {'─' * 70}")
    print(f"  ANALYTICS RULES ({len(rules)} total)")
    print(f"  {'─' * 70}")

    if not rules:
        print("  No analytics rules found.")
        return

    enabled_count = 0
    disabled_count = 0

    for rule in rules:
        kind = rule.kind or "Unknown"
        name = getattr(rule, "display_name", None) or getattr(rule, "name", "Unknown")
        enabled = getattr(rule, "enabled", None)

        if enabled is True:
            enabled_count += 1
            status_icon = "✅"
        elif enabled is False:
            disabled_count += 1
            status_icon = "❌"
        else:
            status_icon = "❓"

        severity = getattr(rule, "severity", "N/A")
        sev_icon = SEVERITY_COLORS.get(severity, "⚪")

        query_freq = getattr(rule, "query_frequency", None)
        freq_str = str(query_freq) if query_freq else "N/A"

        print(f"\n  {status_icon} {name}")
        print(f"     Kind     : {kind}")
        print(f"     Severity : {sev_icon} {severity}")
        print(f"     Frequency: {freq_str}")

        tactics = getattr(rule, "tactics", [])
        if tactics:
            print(f"     Tactics  : {', '.join(tactics)}")

    print(f"\n  Summary: {enabled_count} enabled, {disabled_count} disabled")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("🔍 Microsoft Sentinel Analyzer")
    print("=" * 70)

    # Validate configuration
    if not SUBSCRIPTION_ID:
        print("❌ Error: AZURE_SUBSCRIPTION_ID environment variable not set.")
        print("   Run: export AZURE_SUBSCRIPTION_ID='your-subscription-id'")
        sys.exit(1)

    print(f"  Subscription : {SUBSCRIPTION_ID}")
    print(f"  Resource Group: {RESOURCE_GROUP}")
    print(f"  Workspace    : {WORKSPACE_NAME}")

    # Initialize client
    print("\n🔐 Authenticating with Azure...")
    try:
        client = get_sentinel_client(SUBSCRIPTION_ID)
        print("  ✅ Authentication successful")
    except Exception as e:
        print(f"  ❌ Authentication failed: {e}")
        sys.exit(1)

    # ── 1. List all open incidents ────────────────────────────────────────────
    print("\n📋 Fetching open incidents...")
    open_incidents = list_incidents(
        client, RESOURCE_GROUP, WORKSPACE_NAME,
        status_filter="New",
        top=50,
    )
    print(f"  Found {len(open_incidents)} new incidents")

    # ── 2. List active incidents ──────────────────────────────────────────────
    active_incidents = list_incidents(
        client, RESOURCE_GROUP, WORKSPACE_NAME,
        status_filter="Active",
        top=50,
    )
    print(f"  Found {len(active_incidents)} active incidents")

    all_open = open_incidents + active_incidents

    # ── 3. Get details for top High severity incident ─────────────────────────
    high_incidents = [i for i in all_open if i.severity == "High"]
    if high_incidents:
        top_incident = high_incidents[0]
        incident_id = top_incident.name  # The resource name is the GUID
        print(f"\n🔎 Getting details for top High incident: #{top_incident.incident_number}")
        details = get_incident_details(
            client, RESOURCE_GROUP, WORKSPACE_NAME, incident_id
        )
        if details.get("entities"):
            print(f"  Entities found: {len(details['entities'])}")
            for entity in details["entities"]:
                print(f"    • {entity['kind']}: {entity.get('value', 'N/A')}")

    # ── 4. List analytics rules ───────────────────────────────────────────────
    print("\n📏 Fetching analytics rules...")
    rules = list_analytics_rules(client, RESOURCE_GROUP, WORKSPACE_NAME)
    print(f"  Found {len(rules)} analytics rules")

    # ── 5. Print full report ──────────────────────────────────────────────────
    print_incident_report(all_open, WORKSPACE_NAME)
    print_analytics_rules_report(rules)

    # ── 6. High severity summary ──────────────────────────────────────────────
    print(f"\n{'=' * 70}")
    print("  ACTION REQUIRED")
    print(f"{'=' * 70}")

    if high_incidents:
        print(f"\n  🔴 {len(high_incidents)} HIGH severity incident(s) require immediate attention:")
        for inc in high_incidents[:5]:
            print(f"    • #{inc.incident_number}: {inc.title}")
    else:
        print("\n  ✅ No High severity incidents. Good posture!")

    print(f"\n  Report complete. {len(all_open)} open incidents total.\n")


if __name__ == "__main__":
    main()
