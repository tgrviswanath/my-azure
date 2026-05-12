# Project 0.3 — Git Workflow

## What This Does
Establishes a professional Git workflow using feature branches, conventional commits, pull request simulation, semantic versioning, and GitHub Actions basics. This is the foundation for all future Azure projects.

## Tools Used
| Tool | Purpose |
|------|---------|
| Git | Version control |
| GitHub / Azure DevOps | Remote repository hosting |
| Conventional Commits | Standardized commit message format |
| Semantic Versioning | Version tagging (v1.0.0) |
| GitHub Actions | CI/CD automation |

## Workflow Overview
```
main ──────────────────────────────────────────► (production)
  │                                    ▲
  └─► develop ──────────────────────► merge
           │                  ▲
           └─► feature/xyz ──►
```

## How to Run
```bash
bash code/git_workflow_demo.sh
```

## Folder Structure
```
project_0.3_git_workflow/
├── README.md
├── steps.md
├── cost_estimate.md
├── docs/
│   └── architecture.md
└── code/
    └── git_workflow_demo.sh
```

## Conventional Commit Types
| Type | When to Use |
|------|------------|
| `feat:` | New feature |
| `fix:` | Bug fix |
| `docs:` | Documentation only |
| `chore:` | Build/tooling changes |
| `refactor:` | Code restructure, no behavior change |
| `test:` | Adding or fixing tests |
| `ci:` | CI/CD pipeline changes |

## Lessons Learned
- Always branch from `develop`, not `main`
- Squash commits before merging to keep history clean
- Tag releases on `main` only, never on feature branches
- `git log --oneline --graph` gives a visual branch history
- Conventional commits enable automated changelog generation
- `git stash` saves work-in-progress before switching branches
