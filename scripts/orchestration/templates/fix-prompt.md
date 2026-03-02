You are working on code in {{WORKSPACE}}. This is a git worktree on branch {{BRANCH}}.

Review findings need to be addressed. Apply ALL fixes below, then commit and push.

{{FIXES}}

## Commit Rules
- Use `git add <specific-files>` — NEVER use `git add .` or `git add -A`
- Never commit: .mise.toml, .sisyphus/boulder.json, .env, *.log, node_modules/
- Check `git status` before every commit
- Commit message: {{COMMIT_MESSAGE}}
- After committing, push to origin: `git push origin {{BRANCH}}`
