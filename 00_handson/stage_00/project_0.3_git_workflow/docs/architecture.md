# Architecture — Project 0.3 Git Workflow

## Branching Diagram

```
  Time ──────────────────────────────────────────────────────►

  main     ●─────────────────────────────────────────●──► v1.0.0
            \                                       /
  develop    ●──────────────────────────────────●──►
              \                          \     /
  feature/A    ●──●──●──► (squash) ──────►   /
                                             /
  feature/B              ●──●──●────────────►
                         (hotfix/bug)
```

## Git Flow Summary

```
┌─────────────────────────────────────────────────────────┐
│                    Git Workflow                          │
│                                                          │
│  1. Developer creates feature branch from develop        │
│     git checkout -b feature/my-feature develop           │
│                                                          │
│  2. Developer makes commits (conventional format)        │
│     feat: add new function                               │
│     fix: handle edge case                                │
│     docs: update README                                  │
│                                                          │
│  3. Push branch and open Pull Request                    │
│     git push -u origin feature/my-feature                │
│     → PR: feature/my-feature → develop                   │
│                                                          │
│  4. Code review + CI checks pass                         │
│     → Squash and merge into develop                      │
│                                                          │
│  5. Release: merge develop → main + tag                  │
│     git tag -a v1.0.0 -m "Release v1.0.0"               │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## Conventional Commit Format

```
<type>(<scope>): <short description>

[optional body]

[optional footer]
```

Examples:
```
feat(storage): add blob upload with retry logic
fix(auth): handle token expiry gracefully
docs(readme): add deployment instructions
chore(deps): upgrade azure-storage-blob to 12.19.0
test(blob): add unit tests for upload function
ci(github): add lint check to PR workflow
```

## Key Concepts

| Concept | Explanation |
|---------|-------------|
| `main` | Production-ready code only — never commit directly |
| `develop` | Integration branch — all features merge here first |
| `feature/*` | Short-lived branches for individual features |
| `hotfix/*` | Emergency fixes branched from main |
| Conventional Commits | Structured format enabling automated changelogs |
| Semantic Versioning | `MAJOR.MINOR.PATCH` — v1.2.3 |
| Squash merge | Collapses feature commits into one clean commit |
| `--no-ff` | Preserves merge commit in history (shows branch existed) |
