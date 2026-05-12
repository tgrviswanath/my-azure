"""
oidc_setup.py — Create Azure AD App Registration + federated credential for GitHub Actions OIDC.

Usage:
    pip install azure-identity azure-mgmt-authorization
    python code/oidc_setup.py --repo myorg/my-app --role Contributor
"""

import argparse
import json
import subprocess
import sys


def run_az(args: list[str]) -> str:
    """Run an Azure CLI command and return stdout."""
    result = subprocess.run(["az"] + args, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"[ERR] az {' '.join(args)}\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def setup_oidc(repo: str, branch: str, role: str) -> None:
    print(f"\n{'='*60}")
    print("  GitHub Actions OIDC Setup for Azure")
    print(f"{'='*60}")
    print(f"  Repo   : {repo}")
    print(f"  Branch : {branch}")
    print(f"  Role   : {role}\n")

    # Get subscription and tenant
    account = json.loads(run_az(["account", "show"]))
    subscription_id = account["id"]
    tenant_id = account["tenantId"]

    # Create App Registration
    print("[*] Creating App Registration...")
    app_name = f"github-actions-{repo.replace('/', '-')}"
    app_id = run_az(["ad", "app", "create", "--display-name", app_name, "--query", "appId", "-o", "tsv"])
    print(f"[+] App Registration created: {app_id}")

    # Create Service Principal
    print("[*] Creating Service Principal...")
    sp_oid = run_az(["ad", "sp", "create", "--id", app_id, "--query", "id", "-o", "tsv"])
    print(f"[+] Service Principal: {sp_oid}")

    # Add federated credential for branch
    print(f"[*] Adding federated credential for branch '{branch}'...")
    cred_params = json.dumps({
        "name": f"github-{branch.replace('/', '-')}",
        "issuer": "https://token.actions.githubusercontent.com",
        "subject": f"repo:{repo}:ref:refs/heads/{branch}",
        "audiences": ["api://AzureADTokenExchange"]
    })
    run_az(["ad", "app", "federated-credential", "create", "--id", app_id, "--parameters", cred_params])
    print("[+] Federated credential (branch) added.")

    # Add federated credential for PRs
    print("[*] Adding federated credential for pull requests...")
    pr_params = json.dumps({
        "name": "github-pull-requests",
        "issuer": "https://token.actions.githubusercontent.com",
        "subject": f"repo:{repo}:pull_request",
        "audiences": ["api://AzureADTokenExchange"]
    })
    run_az(["ad", "app", "federated-credential", "create", "--id", app_id, "--parameters", pr_params])
    print("[+] Federated credential (PR) added.")

    # Assign RBAC role
    print(f"[*] Assigning '{role}' role at subscription scope...")
    run_az(["role", "assignment", "create",
            "--assignee", sp_oid,
            "--role", role,
            "--scope", f"/subscriptions/{subscription_id}"])
    print(f"[+] Role '{role}' assigned.")

    # Print summary
    print(f"\n{'='*60}")
    print("  Setup Complete — Add these to GitHub Secrets:")
    print(f"{'='*60}")
    print(f"  AZURE_CLIENT_ID       = {app_id}")
    print(f"  AZURE_TENANT_ID       = {tenant_id}")
    print(f"  AZURE_SUBSCRIPTION_ID = {subscription_id}")
    print(f"\n  GitHub Actions workflow snippet:")
    print("""
  - name: Azure Login
    uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
""")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo",   required=True, help="GitHub repo (org/repo)")
    parser.add_argument("--branch", default="main")
    parser.add_argument("--role",   default="Contributor")
    args = parser.parse_args()
    setup_oidc(args.repo, args.branch, args.role)
