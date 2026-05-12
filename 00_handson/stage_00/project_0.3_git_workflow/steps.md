# Steps — Project 0.3 Git Workflow

## Phase 1 — Initialize Repository

### 1.1 Create and initialize a new repo
```bash
mkdir azure-git-lab && cd azure-git-lab
git init
git config user.name "Your Name"
git config user.email "you@example.com"
```

### 1.2 Create initial files
```bash
echo "# Azure Git Lab" > README.md
echo "*.pyc" > .gitignore
echo "__pycache__/" >> .gitignore
echo ".env" >> .gitignore
```

### 1.3 First commit on main
```bash
git add .
git commit -m "chore: initial project setup"
```

### 1.4 Create develop branch
```bash
git checkout -b develop
git push -u origin develop  # if remote exists
```

---

## Phase 2 — Feature Branch Workflow

### 2.1 Create a feature branch
```bash
git checkout develop
git checkout -b feature/add-blob-uploader
```

### 2.2 Make changes
```bash
cat > blob_uploader.py <<'EOF'
def upload_blob(container, filename):
    """Upload a file to Azure Blob Storage."""
    print(f"Uploading {filename} to {container}")
EOF
```

### 2.3 Stage and commit with conventional commit
```bash
git add blob_uploader.py
git commit -m "feat: add blob uploader function"
```

### 2.4 Add more commits
```bash
echo "# Blob Uploader" > blob_uploader_docs.md
git add blob_uploader_docs.md
git commit -m "docs: add blob uploader documentation"

# Fix a bug
echo "    return True" >> blob_uploader.py
git add blob_uploader.py
git commit -m "fix: return success status from upload_blob"
```

---

## Phase 3 — Conventional Commits Practice

### 3.1 View commit types in action
```bash
git log --oneline
```

### 3.2 Amend the last commit message (if needed)
```bash
git commit --amend -m "fix: return success boolean from upload_blob"
```

### 3.3 Interactive rebase to squash commits
```bash
git rebase -i HEAD~3
# In editor: change 'pick' to 'squash' for commits 2 and 3
# Result: 3 commits become 1 clean commit
```

---

## Phase 4 — Pull Request Simulation

### 4.1 Push feature branch
```bash
git push -u origin feature/add-blob-uploader
```

### 4.2 Merge into develop (simulating PR approval)
```bash
git checkout develop
git merge --no-ff feature/add-blob-uploader -m "feat: merge blob uploader feature"
git branch -d feature/add-blob-uploader
```

### 4.3 View the merge graph
```bash
git log --oneline --graph --all
```

---

## Phase 5 — Merge and Tag Release

### 5.1 Merge develop into main
```bash
git checkout main
git merge --no-ff develop -m "chore: release v1.0.0"
```

### 5.2 Tag the release
```bash
git tag -a v1.0.0 -m "Release v1.0.0 — blob uploader feature"
git log --oneline --graph
```

### 5.3 Push tags
```bash
git push origin main --tags
```

### 5.4 View all tags
```bash
git tag -l
git show v1.0.0
```

---

## Screenshots to Take
- [ ] `git log --oneline --graph --all` showing branch structure
- [ ] Conventional commit messages in log
- [ ] Tag created with `git tag -l`
- [ ] Merge commit showing feature branch merged into develop
