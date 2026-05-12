"""
secrets_client.py — Azure Key Vault secrets management.

Usage:
    pip install azure-identity azure-keyvault-secrets
    export KEY_VAULT_URL=https://kv-handson-001.vault.azure.net/
    python code/secrets_client.py --vault-url $KEY_VAULT_URL
"""

import argparse
import sys
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.core.exceptions import ResourceNotFoundError, HttpResponseError


def get_client(vault_url: str) -> SecretClient:
    credential = DefaultAzureCredential()
    return SecretClient(vault_url=vault_url, credential=credential)


def get_secret(client: SecretClient, name: str) -> str:
    """Retrieve a secret value. Never log the value."""
    secret = client.get_secret(name)
    print(f"[+] Retrieved secret '{name}' (version: {secret.properties.version[:8]}...)")
    return secret.value


def list_secrets(client: SecretClient) -> None:
    """List all secret names (not values)."""
    print("\n[*] Secrets in Key Vault:")
    secrets = client.list_properties_of_secrets()
    for s in secrets:
        enabled = "enabled" if s.enabled else "disabled"
        print(f"    - {s.name:<30} [{enabled}] updated: {s.updated_on.strftime('%Y-%m-%d') if s.updated_on else 'N/A'}")


def set_secret(client: SecretClient, name: str, value: str) -> None:
    """Store or update a secret."""
    client.set_secret(name, value)
    print(f"[+] Secret '{name}' stored/updated.")


def rotate_secret(client: SecretClient, name: str, new_value: str) -> None:
    """Rotate a secret — creates new version, disables old."""
    # Get current version
    try:
        current = client.get_secret(name)
        old_version = current.properties.version
    except ResourceNotFoundError:
        old_version = None

    # Set new version
    client.set_secret(name, new_value)
    print(f"[+] Secret '{name}' rotated — new version created.")

    # Disable old version
    if old_version:
        client.update_secret_properties(name, version=old_version, enabled=False)
        print(f"[+] Old version {old_version[:8]}... disabled.")


def demo(vault_url: str) -> None:
    print(f"\n{'='*60}")
    print(f"  Azure Key Vault Demo")
    print(f"{'='*60}")
    print(f"  Vault: {vault_url}\n")

    client = get_client(vault_url)

    # List existing secrets
    list_secrets(client)

    # Read a secret (value used but not printed)
    try:
        db_pass = get_secret(client, "db-password")
        # Use the secret — connect to DB, etc.
        print(f"[+] DB connection would use password (length: {len(db_pass)} chars)")
    except ResourceNotFoundError:
        print("[!] Secret 'db-password' not found — run terraform apply first")

    print(f"\n[+] Demo complete. Secrets accessed securely via Managed Identity.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--vault-url", required=True, help="Key Vault URI")
    args = parser.parse_args()
    demo(args.vault_url)
