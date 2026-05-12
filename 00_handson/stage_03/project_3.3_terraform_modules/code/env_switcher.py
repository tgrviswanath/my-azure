"""
env_switcher.py — Switch between Terraform workspaces for dev/qa/prod.

Usage:
    python env_switcher.py --env dev
    python env_switcher.py --env qa --action plan
    python env_switcher.py --env prod --action apply   # Requires confirmation
    python env_switcher.py --show-costs

Requirements:
    terraform must be installed and in PATH
"""

import argparse
import subprocess
import sys
from pathlib import Path


# ─────────────────────────────────────────────
# Cost estimates per environment
# ─────────────────────────────────────────────

COST_ESTIMATES = {
    "dev": {
        "vm": "$7.59 (B1s x1)",
        "sql": "$4.99 (Basic)",
        "appgw": "$0 (not deployed in dev)",
        "total": "~$50/month",
        "color": "\033[92m",  # green
    },
    "qa": {
        "vm": "$60.74 (B2s x2)",
        "sql": "$30.00 (S1)",
        "appgw": "$125.00 (Standard_v2)",
        "total": "~$100/month",
        "color": "\033[93m",  # yellow
    },
    "prod": {
        "vm": "$560.64 (D4s_v3 x4)",
        "sql": "$465.00 (P1)",
        "appgw": "$250.00 (WAF_v2 x3 CU)",
        "total": "~$300–1,300/month",
        "color": "\033[91m",  # red
    },
}

RESET = "\033[0m"
BOLD = "\033[1m"


def show_costs() -> None:
    print("\n╔══════════════════════════════════════════════════════════╗")
    print("║              Environment Cost Estimates                  ║")
    print("╚══════════════════════════════════════════════════════════╝\n")

    for env, costs in COST_ESTIMATES.items():
        color = costs["color"]
        print(f"  {color}{BOLD}{env.upper()}{RESET}")
        print(f"    VM:       {costs['vm']}")
        print(f"    SQL:      {costs['sql']}")
        print(f"    App GW:   {costs['appgw']}")
        print(f"    {BOLD}Total:    {costs['total']}{RESET}\n")


# ─────────────────────────────────────────────
# Terraform workspace management
# ─────────────────────────────────────────────

def find_terraform_dir() -> Path:
    script_dir = Path(__file__).parent
    tf_dir = script_dir.parent / "terraform"
    if tf_dir.exists():
        return tf_dir
    if Path("main.tf").exists():
        return Path(".")
    raise FileNotFoundError("Cannot find terraform directory")


def run(cmd: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess:
    print(f"\n  \033[94m$\033[0m {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=str(cwd), capture_output=False)
    if check and result.returncode != 0:
        print(f"\n  \033[91m✘ Command failed (exit {result.returncode})\033[0m")
        sys.exit(result.returncode)
    return result


def get_current_workspace(tf_dir: Path) -> str:
    result = subprocess.run(
        ["terraform", "workspace", "show"],
        cwd=str(tf_dir),
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def list_workspaces(tf_dir: Path) -> list[str]:
    result = subprocess.run(
        ["terraform", "workspace", "list"],
        cwd=str(tf_dir),
        capture_output=True,
        text=True,
    )
    workspaces = []
    for line in result.stdout.strip().split("\n"):
        ws = line.strip().lstrip("* ").strip()
        if ws:
            workspaces.append(ws)
    return workspaces


def switch_workspace(tf_dir: Path, env: str) -> None:
    existing = list_workspaces(tf_dir)
    if env in existing:
        run(["terraform", "workspace", "select", env], tf_dir)
    else:
        run(["terraform", "workspace", "new", env], tf_dir)
    print(f"\n  \033[92m✔\033[0m  Switched to workspace: {env}")


def confirm_prod() -> bool:
    costs = COST_ESTIMATES["prod"]
    print(f"\n  \033[91m{'═' * 55}\033[0m")
    print(f"  \033[91m  ⚠  WARNING: You are about to operate on PRODUCTION\033[0m")
    print(f"  \033[91m{'═' * 55}\033[0m")
    print(f"\n  Estimated cost: {costs['total']}")
    print(f"  VM:    {costs['vm']}")
    print(f"  SQL:   {costs['sql']}")
    print(f"  AppGW: {costs['appgw']}")
    print()
    answer = input("  Type 'yes' to confirm PROD operation: ")
    return answer.strip().lower() == "yes"


# ─────────────────────────────────────────────
# Actions
# ─────────────────────────────────────────────

def action_switch(tf_dir: Path, env: str) -> None:
    """Just switch workspace, no terraform commands."""
    current = get_current_workspace(tf_dir)
    print(f"\n  Current workspace: {current}")
    if current == env:
        print(f"  Already on workspace: {env}")
        return
    switch_workspace(tf_dir, env)


def action_plan(tf_dir: Path, env: str) -> None:
    switch_workspace(tf_dir, env)
    var_file = tf_dir / "envs" / f"{env}.tfvars"
    if not var_file.exists():
        print(f"  \033[91m✘\033[0m  var file not found: {var_file}")
        sys.exit(1)
    run(["terraform", "plan", f"-var-file=envs/{env}.tfvars", f"-out=tfplan-{env}"], tf_dir)


def action_apply(tf_dir: Path, env: str) -> None:
    if env == "prod":
        if not confirm_prod():
            print("\n  Cancelled.")
            sys.exit(0)

    switch_workspace(tf_dir, env)
    plan_file = tf_dir / f"tfplan-{env}"

    if plan_file.exists():
        run(["terraform", "apply", f"tfplan-{env}"], tf_dir)
    else:
        print(f"  \033[93m⚠\033[0m  No saved plan found. Running plan first...")
        action_plan(tf_dir, env)
        run(["terraform", "apply", f"tfplan-{env}"], tf_dir)


def action_destroy(tf_dir: Path, env: str) -> None:
    if env == "prod":
        if not confirm_prod():
            print("\n  Cancelled.")
            sys.exit(0)

    switch_workspace(tf_dir, env)
    var_file = f"envs/{env}.tfvars"
    run(["terraform", "destroy", f"-var-file={var_file}", "-auto-approve"], tf_dir)


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Terraform environment switcher")
    parser.add_argument("--env", choices=["dev", "qa", "prod"], help="Target environment")
    parser.add_argument(
        "--action",
        choices=["switch", "plan", "apply", "destroy"],
        default="switch",
        help="Action to perform (default: switch)",
    )
    parser.add_argument("--show-costs", action="store_true", help="Show cost estimates and exit")
    parser.add_argument("--tf-dir", help="Path to terraform directory")
    args = parser.parse_args()

    print("\n╔══════════════════════════════════════════════════════════╗")
    print("║           Terraform Environment Switcher                 ║")
    print("╚══════════════════════════════════════════════════════════╝")

    if args.show_costs:
        show_costs()
        return

    if not args.env:
        parser.error("--env is required unless --show-costs is used")

    tf_dir = Path(args.tf_dir) if args.tf_dir else find_terraform_dir()
    print(f"\n  Environment: {BOLD}{args.env.upper()}{RESET}")
    print(f"  Action:      {args.action}")
    print(f"  TF dir:      {tf_dir.resolve()}")

    # Show cost for target env
    costs = COST_ESTIMATES[args.env]
    print(f"  Est. cost:   {costs['color']}{costs['total']}{RESET}")

    action_map = {
        "switch":  lambda: action_switch(tf_dir, args.env),
        "plan":    lambda: action_plan(tf_dir, args.env),
        "apply":   lambda: action_apply(tf_dir, args.env),
        "destroy": lambda: action_destroy(tf_dir, args.env),
    }

    action_map[args.action]()

    # Show current workspace after action
    current = get_current_workspace(tf_dir)
    print(f"\n  \033[92m✔\033[0m  Current workspace: {current}")

    # List all workspaces
    workspaces = list_workspaces(tf_dir)
    print(f"  All workspaces: {', '.join(workspaces)}\n")


if __name__ == "__main__":
    main()
