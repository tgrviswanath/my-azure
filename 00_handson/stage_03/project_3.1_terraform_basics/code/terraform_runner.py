"""
terraform_runner.py — Python wrapper for Terraform CLI commands.

Provides colored output, error handling, and JSON output parsing.

Usage:
    python terraform_runner.py init
    python terraform_runner.py fmt
    python terraform_runner.py validate
    python terraform_runner.py plan
    python terraform_runner.py apply
    python terraform_runner.py output
    python terraform_runner.py destroy
    python terraform_runner.py state-list

Requirements:
    terraform must be installed and in PATH
    az login must be run first
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


# ─────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────

class Color:
    GREEN  = "\033[92m"
    YELLOW = "\033[93m"
    RED    = "\033[91m"
    BLUE   = "\033[94m"
    CYAN   = "\033[96m"
    BOLD   = "\033[1m"
    RESET  = "\033[0m"

def green(s: str) -> str:  return f"{Color.GREEN}{s}{Color.RESET}"
def yellow(s: str) -> str: return f"{Color.YELLOW}{s}{Color.RESET}"
def red(s: str) -> str:    return f"{Color.RED}{s}{Color.RESET}"
def blue(s: str) -> str:   return f"{Color.BLUE}{s}{Color.RESET}"
def bold(s: str) -> str:   return f"{Color.BOLD}{s}{Color.RESET}"


# ─────────────────────────────────────────────
# Terraform runner
# ─────────────────────────────────────────────

def find_terraform_dir() -> Path:
    """Find the terraform directory relative to this script."""
    script_dir = Path(__file__).parent
    # Try ../terraform/ relative to code/
    tf_dir = script_dir.parent / "terraform"
    if tf_dir.exists():
        return tf_dir
    # Try current directory
    if Path("main.tf").exists():
        return Path(".")
    # Try terraform/ in current directory
    if Path("terraform/main.tf").exists():
        return Path("terraform")
    raise FileNotFoundError(
        "Could not find terraform directory. "
        "Run from the project root or terraform/ directory."
    )


def run_terraform(
    args: list[str],
    cwd: Path,
    capture_output: bool = False,
    auto_approve: bool = False,
) -> tuple[int, str, str]:
    """Run a terraform command and return (returncode, stdout, stderr)."""
    cmd = ["terraform"] + args
    if auto_approve and "apply" in args or "destroy" in args:
        if "-auto-approve" not in cmd:
            cmd.append("-auto-approve")

    print(f"\n{blue('$')} {bold(' '.join(cmd))}")
    print(f"  {yellow('cwd:')} {cwd}\n")

    if capture_output:
        result = subprocess.run(
            cmd,
            cwd=str(cwd),
            capture_output=True,
            text=True,
        )
        return result.returncode, result.stdout, result.stderr
    else:
        result = subprocess.run(cmd, cwd=str(cwd))
        return result.returncode, "", ""


def check_terraform_installed() -> None:
    """Verify terraform is installed."""
    try:
        result = subprocess.run(
            ["terraform", "version", "-json"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)
            version = data.get("terraform_version", "unknown")
            print(green(f"✔  Terraform {version} found"))
        else:
            print(yellow("⚠  terraform version check failed"))
    except FileNotFoundError:
        print(red("✘  Terraform not found in PATH"))
        print("   Install: https://developer.hashicorp.com/terraform/install")
        sys.exit(1)


# ─────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────

def cmd_init(tf_dir: Path) -> int:
    print(bold("\n=== terraform init ==="))
    print("Downloads provider plugins and sets up the working directory.\n")
    rc, _, _ = run_terraform(["init", "-upgrade"], tf_dir)
    if rc == 0:
        print(green("\n✔  Initialization complete"))
        print("   Provider plugins downloaded to .terraform/")
        print("   Lock file updated: .terraform.lock.hcl")
    else:
        print(red("\n✘  Initialization failed"))
    return rc


def cmd_fmt(tf_dir: Path) -> int:
    print(bold("\n=== terraform fmt ==="))
    print("Formats .tf files to canonical style.\n")
    rc, stdout, _ = run_terraform(["fmt", "-recursive", "-diff"], tf_dir, capture_output=True)
    if stdout.strip():
        print(yellow("Files reformatted:"))
        for line in stdout.strip().split("\n"):
            print(f"  {line}")
    else:
        print(green("✔  All files already formatted"))
    return rc


def cmd_validate(tf_dir: Path) -> int:
    print(bold("\n=== terraform validate ==="))
    print("Checks configuration syntax and internal consistency.\n")
    rc, stdout, stderr = run_terraform(["validate", "-json"], tf_dir, capture_output=True)
    try:
        data = json.loads(stdout)
        if data.get("valid"):
            print(green("✔  Configuration is valid"))
        else:
            print(red("✘  Validation failed:"))
            for diag in data.get("diagnostics", []):
                severity = diag.get("severity", "error")
                summary = diag.get("summary", "")
                detail = diag.get("detail", "")
                color = red if severity == "error" else yellow
                print(f"  {color(severity.upper())}: {summary}")
                if detail:
                    print(f"    {detail}")
    except json.JSONDecodeError:
        print(stdout or stderr)
    return rc


def cmd_plan(tf_dir: Path, var_file: str | None = None) -> int:
    print(bold("\n=== terraform plan ==="))
    print("Shows what changes will be made without applying them.\n")
    args = ["plan", "-out=tfplan"]
    if var_file:
        args.extend([f"-var-file={var_file}"])
    rc, _, _ = run_terraform(args, tf_dir)
    if rc == 0:
        print(green("\n✔  Plan saved to tfplan"))
        print("   Run 'apply' to execute this plan")
    else:
        print(red("\n✘  Plan failed"))
    return rc


def cmd_apply(tf_dir: Path, auto_approve: bool = False) -> int:
    print(bold("\n=== terraform apply ==="))
    print("Creates or updates resources in Azure.\n")

    if Path(tf_dir / "tfplan").exists():
        args = ["apply", "tfplan"]
    else:
        args = ["apply"]
        if auto_approve:
            args.append("-auto-approve")

    rc, _, _ = run_terraform(args, tf_dir)
    if rc == 0:
        print(green("\n✔  Apply complete"))
        print("   Resources created/updated in Azure")
        print("   State saved to terraform.tfstate")
    else:
        print(red("\n✘  Apply failed"))
    return rc


def cmd_output(tf_dir: Path) -> int:
    print(bold("\n=== terraform output ==="))
    print("Shows output values from the current state.\n")
    rc, stdout, _ = run_terraform(["output", "-json"], tf_dir, capture_output=True)
    if rc == 0 and stdout.strip():
        try:
            outputs = json.loads(stdout)
            if outputs:
                print(f"  {'Output':<40} {'Value'}")
                print(f"  {'─' * 70}")
                for name, data in outputs.items():
                    value = data.get("value", "")
                    sensitive = data.get("sensitive", False)
                    display = "(sensitive)" if sensitive else str(value)
                    print(f"  {name:<40} {display}")
            else:
                print(yellow("  No outputs defined"))
        except json.JSONDecodeError:
            print(stdout)
    else:
        print(yellow("  No outputs available (run apply first)"))
    return rc


def cmd_state_list(tf_dir: Path) -> int:
    print(bold("\n=== terraform state list ==="))
    print("Lists all resources tracked in the state file.\n")
    rc, stdout, _ = run_terraform(["state", "list"], tf_dir, capture_output=True)
    if rc == 0 and stdout.strip():
        resources = stdout.strip().split("\n")
        print(f"  {len(resources)} resource(s) in state:")
        for r in resources:
            print(f"  {green('•')} {r}")
    else:
        print(yellow("  No resources in state (run apply first)"))
    return rc


def cmd_destroy(tf_dir: Path, auto_approve: bool = False) -> int:
    print(bold("\n=== terraform destroy ==="))
    print(red("WARNING: This will DELETE all resources managed by this Terraform configuration.\n"))

    if not auto_approve:
        confirm = input("  Type 'yes' to confirm destruction: ")
        if confirm.strip().lower() != "yes":
            print(yellow("  Destruction cancelled"))
            return 0

    args = ["destroy"]
    if auto_approve:
        args.append("-auto-approve")

    rc, _, _ = run_terraform(args, tf_dir)
    if rc == 0:
        print(green("\n✔  Destroy complete"))
        print("   All resources deleted from Azure")
    else:
        print(red("\n✘  Destroy failed"))
    return rc


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

COMMANDS = {
    "init": "Initialize Terraform working directory",
    "fmt": "Format .tf files",
    "validate": "Validate configuration",
    "plan": "Preview changes",
    "apply": "Apply changes to Azure",
    "output": "Show output values",
    "state-list": "List resources in state",
    "destroy": "Destroy all resources",
}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Terraform runner with colored output",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="\n".join(f"  {cmd:<15} {desc}" for cmd, desc in COMMANDS.items()),
    )
    parser.add_argument("command", choices=list(COMMANDS.keys()), help="Terraform command to run")
    parser.add_argument("--tf-dir", help="Path to terraform directory (auto-detected if omitted)")
    parser.add_argument("--var-file", help="Path to .tfvars file (plan command)")
    parser.add_argument("--auto-approve", action="store_true", help="Skip confirmation prompts")
    args = parser.parse_args()

    print("\n╔══════════════════════════════════════════════════════╗")
    print("║              Terraform Runner                        ║")
    print("╚══════════════════════════════════════════════════════╝")

    check_terraform_installed()

    tf_dir = Path(args.tf_dir) if args.tf_dir else find_terraform_dir()
    print(f"  {blue('Terraform dir:')} {tf_dir.resolve()}\n")

    command_map = {
        "init":       lambda: cmd_init(tf_dir),
        "fmt":        lambda: cmd_fmt(tf_dir),
        "validate":   lambda: cmd_validate(tf_dir),
        "plan":       lambda: cmd_plan(tf_dir, args.var_file),
        "apply":      lambda: cmd_apply(tf_dir, args.auto_approve),
        "output":     lambda: cmd_output(tf_dir),
        "state-list": lambda: cmd_state_list(tf_dir),
        "destroy":    lambda: cmd_destroy(tf_dir, args.auto_approve),
    }

    rc = command_map[args.command]()
    sys.exit(rc)


if __name__ == "__main__":
    main()
