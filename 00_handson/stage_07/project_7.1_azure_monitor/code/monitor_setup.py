"""
monitor_setup.py — Azure Monitor setup automation
Project 7.1: Azure Monitor

Creates alert rules, action groups, and prints a monitoring report
using azure-mgmt-monitor and azure-identity.

Install:
    pip install azure-identity azure-mgmt-monitor azure-mgmt-resource
"""

import os
import sys
from datetime import datetime, timezone, timedelta
from azure.identity import DefaultAzureCredential
from azure.mgmt.monitor import MonitorManagementClient
from azure.mgmt.monitor.models import (
    ActionGroupResource,
    EmailReceiver,
    SmsReceiver,
    WebhookReceiver,
    MetricAlertResource,
    MetricAlertSingleResourceMultipleMetricCriteria,
    MetricCriteria,
    MetricAlertAction,
)
from azure.mgmt.resource import ResourceManagementClient
from azure.core.exceptions import AzureError

# ─── Configuration ────────────────────────────────────────────────────────────

SUBSCRIPTION_ID = os.environ.get("AZURE_SUBSCRIPTION_ID", "")
RESOURCE_GROUP = os.environ.get("AZURE_RESOURCE_GROUP", "rg-monitor-demo")
LOCATION = os.environ.get("AZURE_LOCATION", "eastus")
VM_NAME = os.environ.get("VM_NAME", "vm-monitor-demo")
ALERT_EMAIL = os.environ.get("ALERT_EMAIL", "admin@example.com")

if not SUBSCRIPTION_ID:
    print("ERROR: Set AZURE_SUBSCRIPTION_ID environment variable")
    sys.exit(1)


def get_clients():
    """Initialize Azure SDK clients using DefaultAzureCredential."""
    credential = DefaultAzureCredential()
    monitor_client = MonitorManagementClient(credential, SUBSCRIPTION_ID)
    resource_client = ResourceManagementClient(credential, SUBSCRIPTION_ID)
    return monitor_client, resource_client


def get_vm_resource_id(resource_client: ResourceManagementClient) -> str:
    """Get the full resource ID of the demo VM."""
    resources = resource_client.resources.list_by_resource_group(
        RESOURCE_GROUP,
        filter=f"resourceType eq 'Microsoft.Compute/virtualMachines' and name eq '{VM_NAME}'"
    )
    for r in resources:
        print(f"  Found VM: {r.name} ({r.id})")
        return r.id
    raise ValueError(f"VM '{VM_NAME}' not found in resource group '{RESOURCE_GROUP}'")


def create_action_group(monitor_client: MonitorManagementClient) -> str:
    """Create an action group with email and webhook receivers."""
    print("\n[1/4] Creating Action Group...")

    action_group = ActionGroupResource(
        location="global",
        group_short_name="agmonitor",
        enabled=True,
        email_receivers=[
            EmailReceiver(
                name="admin-email",
                email_address=ALERT_EMAIL,
                use_common_alert_schema=True,
            )
        ],
        sms_receivers=[
            # Uncomment and fill in to enable SMS
            # SmsReceiver(
            #     name="admin-sms",
            #     country_code="1",
            #     phone_number="5551234567",
            # )
        ],
        webhook_receivers=[
            WebhookReceiver(
                name="teams-webhook",
                service_uri="https://outlook.office.com/webhook/placeholder",
                use_common_alert_schema=True,
            )
        ],
        tags={"project": "7.1-azure-monitor"},
    )

    result = monitor_client.action_groups.create_or_update(
        resource_group_name=RESOURCE_GROUP,
        action_group_name="ag-monitor-demo",
        action_group=action_group,
    )

    print(f"  ✓ Action Group created: {result.name}")
    print(f"    ID: {result.id}")
    print(f"    Email: {ALERT_EMAIL}")
    return result.id


def create_cpu_alert(
    monitor_client: MonitorManagementClient,
    vm_resource_id: str,
    action_group_id: str,
) -> str:
    """Create a metric alert rule for high CPU usage."""
    print("\n[2/4] Creating CPU Alert Rule...")

    alert = MetricAlertResource(
        location="global",
        description="Alert when VM CPU exceeds 80% for 5 minutes",
        severity=2,  # Warning
        enabled=True,
        scopes=[vm_resource_id],
        evaluation_frequency="PT1M",   # Check every 1 minute
        window_size="PT5M",            # Over a 5-minute window
        criteria=MetricAlertSingleResourceMultipleMetricCriteria(
            odata_type="Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria",
            all_of=[
                MetricCriteria(
                    name="HighCPU",
                    metric_namespace="Microsoft.Compute/virtualMachines",
                    metric_name="Percentage CPU",
                    operator="GreaterThan",
                    threshold=80.0,
                    time_aggregation="Average",
                    criterion_type="StaticThresholdCriterion",
                )
            ],
        ),
        actions=[
            MetricAlertAction(action_group_id=action_group_id)
        ],
        tags={"project": "7.1-azure-monitor"},
    )

    result = monitor_client.metric_alerts.create_or_update(
        resource_group_name=RESOURCE_GROUP,
        rule_name="alert-cpu-high",
        parameters=alert,
    )

    print(f"  ✓ CPU Alert created: {result.name}")
    print(f"    Condition: CPU > 80% (avg over 5 min)")
    print(f"    Severity: {result.severity} (Warning)")
    print(f"    Frequency: every 1 minute")
    return result.id


def create_disk_alert(
    monitor_client: MonitorManagementClient,
    vm_resource_id: str,
    action_group_id: str,
) -> str:
    """Create a metric alert rule for high disk read throughput."""
    print("\n[3/4] Creating Disk Alert Rule...")

    alert = MetricAlertResource(
        location="global",
        description="Alert when OS disk read bytes/sec exceeds 50MB/s",
        severity=3,  # Informational
        enabled=True,
        scopes=[vm_resource_id],
        evaluation_frequency="PT5M",
        window_size="PT15M",
        criteria=MetricAlertSingleResourceMultipleMetricCriteria(
            odata_type="Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria",
            all_of=[
                MetricCriteria(
                    name="HighDiskRead",
                    metric_namespace="Microsoft.Compute/virtualMachines",
                    metric_name="OS Disk Read Bytes/Sec",
                    operator="GreaterThan",
                    threshold=50_000_000.0,  # 50 MB/s
                    time_aggregation="Average",
                    criterion_type="StaticThresholdCriterion",
                )
            ],
        ),
        actions=[
            MetricAlertAction(action_group_id=action_group_id)
        ],
        tags={"project": "7.1-azure-monitor"},
    )

    result = monitor_client.metric_alerts.create_or_update(
        resource_group_name=RESOURCE_GROUP,
        rule_name="alert-disk-read-high",
        parameters=alert,
    )

    print(f"  ✓ Disk Alert created: {result.name}")
    print(f"    Condition: Disk Read > 50MB/s (avg over 15 min)")
    print(f"    Severity: {result.severity} (Informational)")
    return result.id


def list_alert_rules(monitor_client: MonitorManagementClient) -> list:
    """List all metric alert rules in the resource group."""
    print("\n[4/4] Listing All Alert Rules...")
    alerts = list(monitor_client.metric_alerts.list_by_resource_group(RESOURCE_GROUP))

    if not alerts:
        print("  No alert rules found.")
        return []

    for alert in alerts:
        status = "✓ Enabled" if alert.enabled else "✗ Disabled"
        print(f"  {status} | {alert.name}")
        print(f"           Severity: {alert.severity} | Window: {alert.window_size} | Freq: {alert.evaluation_frequency}")
        if hasattr(alert.criteria, "all_of"):
            for criterion in alert.criteria.all_of:
                print(f"           Condition: {criterion.metric_name} {criterion.operator} {criterion.threshold}")

    return alerts


def get_recent_metric_values(monitor_client: MonitorManagementClient, vm_resource_id: str):
    """Fetch recent CPU metric values for the VM."""
    print("\n[Bonus] Fetching Recent CPU Metrics...")

    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(hours=1)

    try:
        metrics_data = monitor_client.metrics.list(
            resource_uri=vm_resource_id,
            timespan=f"{start_time.isoformat()}/{end_time.isoformat()}",
            interval="PT5M",
            metricnames="Percentage CPU",
            aggregation="Average",
        )

        for metric in metrics_data.value:
            print(f"\n  Metric: {metric.name.localized_value}")
            print(f"  Unit: {metric.unit}")
            for ts in metric.timeseries:
                for dp in ts.data[-6:]:  # Last 6 data points (30 min)
                    if dp.average is not None:
                        ts_str = dp.time_stamp.strftime("%H:%M")
                        bar = "█" * int(dp.average / 5)
                        print(f"    {ts_str}  {dp.average:6.2f}%  {bar}")
    except AzureError as e:
        print(f"  Could not fetch metrics (VM may be off): {e.message}")


def print_monitoring_report(monitor_client: MonitorManagementClient, alerts: list):
    """Print a summary monitoring report."""
    print("\n" + "=" * 60)
    print("  AZURE MONITOR — MONITORING REPORT")
    print("=" * 60)
    print(f"  Subscription:   {SUBSCRIPTION_ID}")
    print(f"  Resource Group: {RESOURCE_GROUP}")
    print(f"  Generated:      {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("-" * 60)
    print(f"  Alert Rules:    {len(alerts)} configured")

    severity_map = {0: "Critical", 1: "Error", 2: "Warning", 3: "Info", 4: "Verbose"}
    enabled_count = sum(1 for a in alerts if a.enabled)
    print(f"  Enabled:        {enabled_count}/{len(alerts)}")

    print("\n  Alert Summary:")
    print(f"  {'Name':<30} {'Severity':<12} {'Status'}")
    print(f"  {'-'*30} {'-'*12} {'-'*10}")
    for alert in alerts:
        sev_name = severity_map.get(alert.severity, str(alert.severity))
        status = "Enabled" if alert.enabled else "Disabled"
        print(f"  {alert.name:<30} {sev_name:<12} {status}")

    print("\n  Notification Channels:")
    print("  - Email:   admin@example.com")
    print("  - Webhook: Teams (configured)")
    print("=" * 60)


def main():
    print("Azure Monitor Setup — Project 7.1")
    print("=" * 40)

    monitor_client, resource_client = get_clients()

    # Get VM resource ID
    print("\nLooking up VM resource ID...")
    try:
        vm_resource_id = get_vm_resource_id(resource_client)
    except ValueError as e:
        print(f"  WARNING: {e}")
        print("  Using placeholder VM ID for demo. Deploy VM first.")
        vm_resource_id = (
            f"/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}"
            f"/providers/Microsoft.Compute/virtualMachines/{VM_NAME}"
        )

    # Create action group
    action_group_id = create_action_group(monitor_client)

    # Create alert rules
    create_cpu_alert(monitor_client, vm_resource_id, action_group_id)
    create_disk_alert(monitor_client, vm_resource_id, action_group_id)

    # List all alerts
    alerts = list_alert_rules(monitor_client)

    # Fetch recent metrics
    get_recent_metric_values(monitor_client, vm_resource_id)

    # Print report
    print_monitoring_report(monitor_client, alerts)

    print("\n✓ Monitor setup complete.")


if __name__ == "__main__":
    main()
