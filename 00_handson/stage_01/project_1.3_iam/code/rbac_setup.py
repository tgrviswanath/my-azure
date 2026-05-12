"""
rbac_setup.py — List and manage Azure RBAC role assignments using the Azure SDK.

Prerequisites:
    pip install azure-mgmt-authorization azure-identity azure-mgmt-msi

Authentication:
    az login   (uses DefaultAzureCredential)

Run:
    python code/rbac_setup.py
"""

import os
import subprocess
from azure.identity import DefaultAzureCredential
from azure.mgmt.authorization import AuthorizationManagementClient
from azure.mgmt.msi import ManagedServiceIdentityClient


def get_subscription_id() -> str:
    sub_id = os.environ.get("AZURE_SUBSCRIPTION_ID")
    if not sub_id:
        result = subprocess.run(
            ["az", "account", "show", "--query", "id", "-o", "tsv"],
            capture_output=True, text=True
        )
        sub_id = result.stdout.strip()
    if not sub_id:
        raise ValueError("Set AZURE_SUBSCRIPTION_ID or run 'az login'")
    return sub_id


def list_role_assignments(auth_client: AuthorizationManagementClient,
                          scope: str) -> None:
    """List all role assignments at a given scope."""
    print(f"\n[*] Role Assignments at scope: {scope.split('/')[-1]}")
    print("-" * 70)

    try:
        assignments = list(auth_client.role_assignments.list_for_scope(scope))

        if not assignments:
            print("  No role assignments found at this scope.")
            return

        print(f"  {'Principal ID':<38} {'Role':<35} {'Type'}")
        print(f"  {'-'*38} {'-'*35} {'-'*20}")

        for assignment in assignments:
            # Get role definition name
            role_def_id = assignment.role_definition_id
            role_name = role_def_id.split("/")[-1] if role_def_id else "Unknown"

            # Try to get friendly role name
            try:
                role_def = auth_client.role_definitions.get_by_id(role_def_id)
                role_name = role_def.role_name
            except Exception:
                pass

            principal_id = assignment.principal_id or "N/A"
            principal_type = assignment.principal_type or "Unknown"

            print(f"  {principal_id:<38} {role_name:<35} {principal_type}")

        print(f"\n  Total: {len(assignments)} assignment(s)")

    except Exception as e:
        print(f"  [!] Error listing role assignments: {e}")


def list_managed_identities(msi_client: ManagedServiceIdentityClient,
                            resource_group: str) -> None:
    """List user-assigned managed identities in a resource group."""
    print(f"\n[*] Managed Identities in: {resource_group}")
    print("-" * 70)

    try:
        identities = list(msi_client.user_assigned_identities.list_by_resource_group(
            resource_group
        ))

        if not identities:
            print("  No user-assigned managed identities found.")
            return

        for identity in identities:
            print(f"  Name:         {identity.name}")
            print(f"  Principal ID: {identity.principal_id}")
            print(f"  Client ID:    {identity.client_id}")
            print(f"  Location:     {identity.location}")
            print()

    except Exception as e:
        print(f"  [!] Error listing managed identities: {e}")


def list_built_in_roles(auth_client: AuthorizationManagementClient,
                        subscription_id: str) -> None:
    """List commonly used built-in roles."""
    print("\n[*] Common Built-in Roles")
    print("-" * 70)

    common_roles = [
        "Owner", "Contributor", "Reader",
        "Storage Blob Data Contributor", "Storage Blob Data Reader",
        "Key Vault Secrets User", "Virtual Machine Contributor"
    ]

    scope = f"/subscriptions/{subscription_id}"
    try:
        all_roles = list(auth_client.role_definitions.list(scope))
        role_map = {r.role_name: r for r in all_roles if r.role_name in common_roles}

        print(f"  {'Role Name':<35} {'Type':<15} {'Description'}")
        print(f"  {'-'*35} {'-'*15} {'-'*40}")

        for role_name in common_roles:
            if role_name in role_map:
                role = role_map[role_name]
                desc = (role.description or "")[:45]
                print(f"  {role_name:<35} {role.role_type:<15} {desc}")

    except Exception as e:
        print(f"  [!] Error listing roles: {e}")


def main():
    print("=" * 70)
    print("  Azure RBAC Setup & Audit Tool")
    print("=" * 70)

    try:
        credential = DefaultAzureCredential()
        subscription_id = get_subscription_id()
        resource_group = os.environ.get("AZURE_RESOURCE_GROUP", "iam-lab-rg")

        print(f"[*] Subscription: {subscription_id}")
        print(f"[*] Resource Group: {resource_group}")

        auth_client = AuthorizationManagementClient(credential, subscription_id)
        msi_client = ManagedServiceIdentityClient(credential, subscription_id)

        # List role assignments at subscription level
        sub_scope = f"/subscriptions/{subscription_id}"
        list_role_assignments(auth_client, sub_scope)

        # List role assignments at resource group level
        rg_scope = f"{sub_scope}/resourceGroups/{resource_group}"
        list_role_assignments(auth_client, rg_scope)

        # List managed identities
        list_managed_identities(msi_client, resource_group)

        # List built-in roles
        list_built_in_roles(auth_client, subscription_id)

        print("\n[+] RBAC audit complete.")

    except Exception as e:
        print(f"\n[!] Error: {e}")
        print("[!] Run 'az login' and ensure you have Reader or Owner role")


if __name__ == "__main__":
    main()
