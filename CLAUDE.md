# riya

Foundry (Solidity) contracts in `src/`, `script/`, `test/`; Next.js app in `frontend/`.

## Commits

When asked to commit, split the work into **atomic commits** — one logical change
per commit, each independently revertable and each leaving the tree buildable.
Never lump unrelated changes into a single commit.

- Stage per-commit with explicit paths (`git add <paths>`), not a blanket `git add -A`.
- Separate contract changes, frontend changes, test changes, and config/dependency
  bumps into their own commits.
- Message format: `<type>(<scope>): <imperative summary>` — e.g.
  `feat(vault): add withdraw fee cap`, `test(vault): cover zero-amount deposit`,
  `chore(deps): bump OZ contracts`.
- Run `git status` before staging and confirm nothing secret is included
  (`.env` is gitignored — keep it that way).
- Push only when explicitly asked.
