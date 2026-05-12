"""
cost_optimizer.py — Find and clean up idle Azure resources.

Usage:
    pip install azure-identity azure-mgmt-compute azure-mgmt-advisor azure-mgmt-monitor
    python code/cost_optimizer.py --dry-run
    python code/cost_optimizer.py --action stop-idle-vms
"""

import argparse
import sys
from datetime import datetime, timedelta, timezone
from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.monitor import MonitorManagementClient
from azure.mgmt.resource import SubscriptionClient


def get_subscription_id() -> str:
    credential = DefaultAzureCredential()
    return list(SubscriptionClient(credential).subscriptions.list())[0].subscription_id


def find_idle_vms(compute: ComputeManagementClient, monitor: MonitorManagementClient,
                  subscription_id: str, cpu_threshold: float = 5.0) -> list[dict]:
    """Find VMs with average CPU < threshold over last 7 days."""
    print(f"\n[*] Scanning for idle VMs (CPU < {cpu_threshold}% over 7 days)...")
    idle_vms = []
    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(days=7)

    for vm in compute.virtual_machines.list_all():
        try:
            metrics = monitor.metrics.list(
                resource_uri=vm.id,
                timespan=f"{start_time.isoformat()}/{end_time.isoformat()}",
                interval="PT1H",
                metricnames="Percentage CPU",
                aggregation="Average"
            )
            values = [p.average for ts in metrics.value for p in ts.timeseries[0].data if p.average is not None] if metrics.value else []
            if values:
                avg_cpu = sum(values) / len(values)
                if avg_cpu < cpu_threshold:
                    idle_vms.append({"name": vm.name, "rg": vm.id.split("/")[4], "avg_cpu": avg_cpu})
                    print(f"  IDLE: {vm.name} (avg CPU: {avg_cpu:.1f}%)")
        except Exception:
            pass

    return idle_vms


def find_unattached_disks(compute: ComputeManagementClient) -> list[dict]:
    """Find managed disks not attached to any VM."""
    print("\n[*] Scanning for unattached disks...")
    unattached = []
    for disk in compute.disks.list():
        if disk.disk_state == "Unattached":
            size_gb = disk.disk_size_gb or 0
            monthly_cost = size_gb * 0.10  # ~$0.10/GB/month for Premium SSD
            unattached.append({"name": disk.name, "rg": disk.id.split("/")[4],
                               "size_gb": size_gb, "monthly_cost": monthly_cost})
            print(f"  UNATTACHED: {disk.name} ({size_gb}GB, ~${monthly_cost:.2f}/month)")
    return unattached


def print_savings_report(idle_vms: list, unattached_disks: list, dry_run: bool) -> None:
    mode = "[DRY RUN]" if dry_run else "[LIVE]"
    print(f"\n{'='*60}")
    print(f"  Cost Optimization Report {mode}")
    print(f"{'='*60}")
    print(f"  Idle VMs found       : {len(idle_vms)}")
    print(f"  Unattached disks     : {len(unattached_disks)}")
    disk_savings = sum(d["monthly_cost"] for d in unattached_disks)
    vm_savings = len(idle_vms) * 30  # ~$30/VM/month estimate
    print(f"  Estimated savings    : ~${vm_savings + disk_savings:.2f}/month")
    print(f"{'='*60}\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="Show what would be done without making changes")
    parser.add_argument("--action", choices=["stop-idle-vms", "delete-disks", "all"], default="all")
    args = parser.parse_args()

    credential = DefaultAzureCredential()
    subscription_id = get_subscription_id()
    compute = ComputeManagementClient(credential, subscription_id)
    monitor = MonitorManagementClient(credential, subscription_id)

    print(f"\n{'='*60}")
    print(f"  Azure Cost Optimizer {'[DRY RUN]' if args.dry_run else '[LIVE]'}")
    print(f"{'='*60}")

    idle_vms = find_idle_vms(compute, monitor, subscription_id)
    unattached_disks = find_unattached_disks(compute)
    print_savings_report(idle_vms, unattached_disks, args.dry_run)

    if not args.dry_run and idle_vms:
        print("[*] Deallocating idle VMs...")
        for vm in idle_vms:
            print(f"  Deallocating {vm['name']}...")
            compute.virtual_machines.begin_deallocate(vm["rg"], vm["name"]).result()
            print(f"  [+] {vm['name']} deallocated.")


if __name__ == "__main__":
    main()
