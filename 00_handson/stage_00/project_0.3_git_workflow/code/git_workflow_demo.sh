#!/bin/bash
# git_workflow_demo.sh — Demonstrates a complete Git workflow
# Creates a temp repo, runs through branching, commits, merge, and tagging
#
# Run: bash code/git_workflow_demo.sh

set -euo pipefail

DEMO_DIR="/tmp/azure-git-demo-$$"
echo "============================================"
echo "  Git Workflow Demo"
echo "  Working in: $DEMO_DIR"
echo "============================================"

# Setup
mkdir -p "$DEMO_DIR"
cd "$DEMO_DIR"
git init
git config user.name "Azure Dev"
git config user.email "dev@azure-lab.local"

echo ""
echo "--- Phase 1: Initial Setup ---"
echo "# Azure Git Lab" > README.md
echo "*.pyc" > .gitignore
echo "__pycache__/" >> .gitignore
git add .
git commit -m "chore: initial project setup"
echo "[+] Initial commit on main"

# Create develop branch
git checkout -b develop
echo "[+] Created develop branch"

echo ""
echo "--- Phase 2: Feature Branch ---"
git checkout -b feature/add-blob-uploader

cat > blob_uploader.py <<'EOF'
"""blob_uploader.py — Upload files to Azure Blob Storage."""

def upload_blob(container_name: str, file_path: str) -> bool:
    """Upload a local file to an Azure Blob container."""
    print(f"Uploading {file_path} to container: {container_name}")
    return True
EOF

git add blob_uploader.py
git commit -m "feat: add blob uploader function"
echo "[+] feat commit: blob uploader"

echo "## Blob Uploader" > blob_uploader_docs.md
echo "Uploads files to Azure Blob Storage." >> blob_uploader_docs.md
git add blob_uploader_docs.md
git commit -m "docs: add blob uploader documentation"
echo "[+] docs commit: documentation"

# Simulate a bug fix
sed -i 's/return True/return True  # success/' blob_uploader.py 2>/dev/null || \
  echo "    # success" >> blob_uploader.py
git add blob_uploader.py
git commit -m "fix: clarify return value in upload_blob"
echo "[+] fix commit: clarify return value"

echo ""
echo "--- Phase 3: View Feature Branch Log ---"
git log --oneline

echo ""
echo "--- Phase 4: Merge Feature into Develop ---"
git checkout develop
git merge --no-ff feature/add-blob-uploader -m "feat: merge blob uploader (#1)"
git branch -d feature/add-blob-uploader
echo "[+] Feature merged into develop"

echo ""
echo "--- Phase 5: Second Feature ---"
git checkout -b feature/add-queue-processor

cat > queue_processor.py <<'EOF'
"""queue_processor.py — Process messages from Azure Queue Storage."""

def process_queue(queue_name: str, max_messages: int = 10) -> list:
    """Receive and process messages from an Azure Queue."""
    print(f"Processing up to {max_messages} messages from: {queue_name}")
    return []
EOF

git add queue_processor.py
git commit -m "feat: add queue processor function"
echo "[+] feat commit: queue processor"

git checkout develop
git merge --no-ff feature/add-queue-processor -m "feat: merge queue processor (#2)"
git branch -d feature/add-queue-processor
echo "[+] Queue processor merged into develop"

echo ""
echo "--- Phase 6: Release to Main ---"
git checkout main
git merge --no-ff develop -m "chore: release v1.0.0"
git tag -a v1.0.0 -m "Release v1.0.0 — blob uploader and queue processor"
echo "[+] Tagged v1.0.0 on main"

echo ""
echo "--- Final: Branch Graph ---"
git log --oneline --graph --all

echo ""
echo "--- Tags ---"
git tag -l

echo ""
echo "============================================"
echo "  Demo Complete!"
echo "  Repo location: $DEMO_DIR"
echo "  Run: cd $DEMO_DIR && git log --oneline --graph --all"
echo "============================================"
