{{TASK_DESCRIPTION}}

## Context
- **Task:** {{TASK_ID}}
- **Repo:** {{REPO_NAME}}
- **Branch:** agent/{{TASK_ID}} (from {{BASE_BRANCH}})
- **Working directory:** {{WORKSPACE}} (use absolute paths — cd here first)

## Constraints
- All file operations must use absolute paths under {{WORKSPACE}}
- Run all shell commands from {{WORKSPACE}} (cd {{WORKSPACE}} && ...)
- Follow existing code style (see AGENTS.md, .cursor/rules/ if present)
- Write tests for new functionality
- Keep commits atomic with descriptive messages
- Use conventional commit format
- Discover how to validate your changes from the repo itself (AGENTS.md, package.json scripts, CI config, pre-commit hooks)

## Communication
- **NEVER use the question tool** - it cannot be answered via API
- Write questions as regular text output in your response
- Questions will be visible in Discord threads and can be answered there

## Commit Rules
- Use `git add <specific-files>` — NEVER use `git add .` or `git add -A`
- Never commit: .mise.toml, .sisyphus/boulder.json, .env, *.log, node_modules/
- Check `git status` before every commit
- Verify `git diff --cached` contains only intended changes
