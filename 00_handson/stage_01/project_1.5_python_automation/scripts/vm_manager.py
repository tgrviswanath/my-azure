"""
vm_manager.py — Start/stop/list Azure VMs using azure-sdk
Usage:
  python vm_manager.py list  --resource-group RG
  python vm_manager.py start --resource-group RG --name VM_NAME
  python vm_manager.py stop  --resource-group RG --name VM_NAME
"""

import argparse
import os
from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient


def get_client() -> ComputeManagementClient:
    credential = DefaultAzureCredential()
    subscription_id = os.environ["AZURE_SUBSCRIPTION_ID"]
    return ComputeManagementClient(credential, subscription_id)


def list_vms(resource_group: str) -> None:
    client = get_client()
    print(f"\nVMs in resource group: {resource_group}")
    print("-" * 70)
    for vm in client.virtual_machines.list(resource_group):
        instance = client.virtual_machines.instance_view(resource_group, vm.name)
        statuses = [s.display_status for s in instance.statuses if s.display_status]
        status = statuses[-1] if statuses else "Unknown"
        print(f"  {vm.name:<40} {vm.hardware_profile.vm_size:<20} {status}")


def start_vm(resource_group: str, vm_name: str) -> None:
    client = get_client()
    print(f"Starting VM: {vm_name}...")
    poller = client.virtual_machines.begin_start(resource_group, vm_name)
    poller.result()
    print(f"✅ VM {vm_name} started")


def stop_vm(resource_group: str, vm_name: str) -> None:
    client = get_client()
    print(f"Deallocating VM: {vm_name}...")
    poller = client.virtual_machines.begin_deallocate(resource_group, vm_name)
    poller.result()
    print(f"✅ VM {vm_name} deallocated (billing stopped)")


def main():
    parser = argparse.ArgumentParser(description="Azure VM manager")
    subparsers = parser.add_subparsers(dest="command")

    list_p = subparsers.add_parser("list")
    list_p.add_argument("--resource-group", required=True)

    start_p = subparsers.add_parser("start")
    start_p.add_argument("--resource-group", required=True)
    start_p.add_argument("--name", required=True)

    stop_p = subparsers.add_parser("stop")
    stop_p.add_argument("--resource-group", required=True)
    stop_p.add_argument("--name", required=True)

    args = parser.parse_args()

    if args.command == "list":
        list_vms(args.resource_group)
    elif args.command == "start":
        start_vm(args.resource_group, args.name)
    elif args.command == "stop":
        stop_vm(args.resource_group, args.name)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
