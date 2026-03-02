#!/bin/bash
# brain-core orchestration script — see docs/orchestration-scripts.md
# setup-workspace.sh — Automated git worktree workspace setup for coding agent tasks
#
# Creates an isolated workspace with:
# - Git worktree from shared repo clone
# - Correct Node.js version via mise
# - Dependencies installed via detected package manager
#
# Usage: setup-workspace.sh <task-id> <repo-url> <base-branch>
#
# Output (stdout): JSON metadata on the last line
# All progress/errors go to stderr
#
# Exit codes:
#   0 — Success
#   1 — Missing arguments or environment
#   2 — Git clone/fetch failed
#   3 — Worktree creation failed
#   4 — Node version detection/installation failed
#   5 — Dependency installation failed

set -euo pipefail

# --- Constants ---
WORKSPACES_ROOT="${WORKSPACES_ROOT:-/opt/opencode}"
REPOS_ROOT="${WORKSPACES_ROOT}/repos"

# --- Logging (all to stderr) ---
log() {
  echo "[setup] $*" >&2
}

# --- Trap: report failure but do NOT auto-cleanup ---
# The orchestrator decides whether to retry or clean up.
cleanup_on_failure() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    log "Setup failed with exit code $exit_code"
  fi
}
trap cleanup_on_failure EXIT

# --- Step 1: Argument validation ---
if [ $# -lt 3 ]; then
  log "Usage: setup-workspace.sh <task-id> <repo-url> <base-branch>"
  exit 1
fi

TASK_ID="$1"
REPO_URL="$2"
BASE_BRANCH="$3"

# Validate task-id: alphanumeric, dots, hyphens, underscores only
if ! [[ "$TASK_ID" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
  log "ERROR: Invalid task-id — must start with alphanumeric, contain only alphanumeric/dots/hyphens/underscores"
  exit 1
fi

AGENT_ID="${AGENT_ID:-default}"
[[ "$AGENT_ID" =~ ^[a-zA-Z0-9_-]+$ ]] || { log "ERROR: invalid AGENT_ID '${AGENT_ID}'"; exit 1; }
SAFE_AGENT_ID="${AGENT_ID//[^A-Za-z0-9_]/_}"
TOKEN_VAR="GITHUB_TOKEN_${SAFE_AGENT_ID}"
GITHUB_TOKEN="${!TOKEN_VAR:-${GITHUB_TOKEN:-}}"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  log "ERROR: missing GitHub token; expected ${TOKEN_VAR} or GITHUB_TOKEN"
  exit 1
fi

# Validate repo URL: must be GitHub HTTPS
if ! [[ "$REPO_URL" =~ ^https://github\.com/ ]]; then
  log "ERROR: Only GitHub HTTPS URLs are supported (got: $REPO_URL)"
  exit 1
fi

# --- Step 2: Derive repo name & paths ---
# Extract repo name: "https://github.com/Org/repo.git" → "repo"
REPO_NAME=$(basename "$REPO_URL" .git)
REPO_DIR="${REPOS_ROOT}/${REPO_NAME}"
WORKSPACE="${WORKSPACES_ROOT}/${TASK_ID}"
BRANCH_NAME="agent/${TASK_ID}"

# --- Step 2.5: Create GIT_ASKPASS helper for authenticated access ---
# Token is never written to .git/config or visible in process list
GIT_ASKPASS_HELPER=$(mktemp "${TMPDIR:-/tmp}/git-askpass-XXXXXX")
printf '#!/bin/bash\necho "%s"\n' "$GITHUB_TOKEN" > "$GIT_ASKPASS_HELPER"
chmod +x "$GIT_ASKPASS_HELPER"

# Clean up helper on exit (append to existing trap)
cleanup_askpass() {
  rm -f "$GIT_ASKPASS_HELPER"
}
trap 'cleanup_on_failure; cleanup_askpass' EXIT

log "Task: $TASK_ID"
log "Repo: $REPO_NAME ($REPO_URL)"
log "Base branch: $BASE_BRANCH"
log "Workspace: $WORKSPACE"
log "Branch: $BRANCH_NAME"

# --- Step 3: Clone or fetch repo ---
if [ -d "$REPO_DIR/.git" ] || [ -f "$REPO_DIR/.git" ]; then
  log "Repo $REPO_NAME already cloned — fetching latest..."
  GIT_ASKPASS="$GIT_ASKPASS_HELPER" git -C "$REPO_DIR" fetch origin >&2 || {
    log "ERROR: git fetch failed for $REPO_NAME"
    exit 2
  }
else
  log "Cloning $REPO_NAME..."
  mkdir -p "$REPOS_ROOT"
  GIT_ASKPASS="$GIT_ASKPASS_HELPER" git clone "$REPO_URL" "$REPO_DIR" >&2 || {
    log "ERROR: git clone failed for $REPO_URL"
    exit 2
  }
fi

# Ensure remote URL is clean (no embedded credentials)
git -C "$REPO_DIR" remote set-url origin "$REPO_URL" 2>/dev/null || true

# --- Step 4: Create git worktree ---
if [ -d "$WORKSPACE" ]; then
  log "Workspace $WORKSPACE already exists — reusing"
else
  log "Creating worktree..."

  # Pre-check branch existence to handle edge cases cleanly
  if git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
    # Local branch exists (e.g., from previous failed run)
    log "Branch $BRANCH_NAME already exists locally — reusing"
    git -C "$REPO_DIR" worktree add "$WORKSPACE" "$BRANCH_NAME" >&2 || {
      log "ERROR: Failed to create worktree from existing branch $BRANCH_NAME"
      exit 3
    }
    # Reset to latest origin base to avoid stale code
    git -C "$WORKSPACE" reset --hard "origin/${BASE_BRANCH}" >&2

  elif git -C "$REPO_DIR" show-ref --verify --quiet "refs/remotes/origin/$BRANCH_NAME" 2>/dev/null; then
    # Branch exists on remote — check out with tracking
    log "Branch $BRANCH_NAME exists on remote — checking out with tracking"
    git -C "$REPO_DIR" worktree add --track "$WORKSPACE" -b "$BRANCH_NAME" "origin/$BRANCH_NAME" >&2 || {
      log "ERROR: Failed to create worktree tracking remote $BRANCH_NAME"
      exit 3
    }

  else
    # Normal case: create new branch from base
    git -C "$REPO_DIR" worktree add "$WORKSPACE" -b "$BRANCH_NAME" "origin/${BASE_BRANCH}" >&2 || {
      log "ERROR: Failed to create worktree for $BRANCH_NAME from origin/${BASE_BRANCH}"
      exit 3
    }
  fi
fi

# --- Step 4.5: Ensure .gitignore covers generated files ---
GITIGNORE_ENTRIES=".mise.toml
.sisyphus/boulder.json
*.log
.env
.env.*
.git-token
.git-credential-helper.sh"

# Ensure file ends with newline before appending (prevents corrupting last line)
if [ -f "$WORKSPACE/.gitignore" ] && [ -s "$WORKSPACE/.gitignore" ]; then
  # Check if file ends with newline; if not, add one
  if [ "$(tail -c 1 "$WORKSPACE/.gitignore" | wc -l)" -eq 0 ]; then
    echo "" >> "$WORKSPACE/.gitignore"
  fi
fi

for entry in $GITIGNORE_ENTRIES; do
  if ! grep -qxF "$entry" "$WORKSPACE/.gitignore" 2>/dev/null; then
    echo "$entry" >> "$WORKSPACE/.gitignore"
  fi
done
log "Ensured .gitignore covers workspace artifacts"

# --- Step 4.6: Persistent credential helper for agent git push ---
# The ephemeral GIT_ASKPASS helper (step 2.5) dies when this script exits.
# Agent sessions run later and need credentials for git push.
# Solution: per-workspace credential helper + token file, configured via git config.
CRED_HELPER="$WORKSPACE/.git-credential-helper.sh"
TOKEN_FILE="$WORKSPACE/.git-token"

# Write token file (restrictive permissions)
printf '%s' "$GITHUB_TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

# Write credential helper script
cat > "$CRED_HELPER" << 'CREDHELPER'
#!/bin/bash
# Reads GitHub token from .git-token file in the same directory.
# Used as git credential helper for agent push operations.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOKEN_FILE="$SCRIPT_DIR/.git-token"
if [ ! -f "$TOKEN_FILE" ]; then
  exit 1
fi
TOKEN=$(cat "$TOKEN_FILE")
echo "protocol=https"
echo "host=github.com"
echo "username=x-access-token"
echo "password=$TOKEN"
echo ""
CREDHELPER
chmod +x "$CRED_HELPER"

# Configure git to use this credential helper (worktree-local config)
git -C "$WORKSPACE" config credential.helper "$CRED_HELPER"
# Also set credential.useHttpPath to avoid leaking to other hosts
git -C "$WORKSPACE" config credential.useHttpPath true

log "Persistent credential helper configured at $CRED_HELPER"

# --- Step 5: Detect Node version ---
detect_node_version() {
  local workspace="$1"
  local version=""

  # Priority: .nvmrc > .node-version > .tool-versions > package.json engines
  if [ -f "$workspace/.nvmrc" ]; then
    version=$(tr -d '[:space:]' < "$workspace/.nvmrc" | sed 's/^v//')
    log "Found .nvmrc: $version"

  elif [ -f "$workspace/.node-version" ]; then
    version=$(tr -d '[:space:]' < "$workspace/.node-version" | sed 's/^v//')
    log "Found .node-version: $version"

  elif [ -f "$workspace/.tool-versions" ]; then
    version=$(grep '^nodejs ' "$workspace/.tool-versions" 2>/dev/null | awk '{print $2}' | sed 's/^v//')
    if [ -n "$version" ]; then
      log "Found .tool-versions: nodejs $version"
    fi

  elif [ -f "$workspace/package.json" ]; then
    # Extract engines.node using python3 (jq not available in this environment)
    version=$(python3 -c "
import json, sys, re
try:
    pkg = json.load(open(sys.argv[1], encoding='utf-8'))
    engines = pkg.get('engines', {}).get('node', '')
    if not engines:
        sys.exit(0)
    m = re.search(r'(\d+)', engines)
    if m:
        print(m.group(1))
except Exception:
    pass
" "$workspace/package.json" 2>/dev/null)
    if [ -n "$version" ]; then
      log "Found package.json engines.node → $version"
    fi
  fi

  # Extract major version only — mise resolves to latest installed minor
  if [ -n "$version" ]; then
    echo "$version" | grep -oE '^[0-9]+' | head -1
  else
    log "No Node version file found — defaulting to 20 (LTS)"
    echo "20"
  fi
}

NODE_VERSION=$(detect_node_version "$WORKSPACE")
log "Node version (major): $NODE_VERSION"

# --- Step 6: Create .mise.toml and install Node ---
cat > "$WORKSPACE/.mise.toml" << EOF
[tools]
node = "$NODE_VERSION"
EOF
log "Created .mise.toml with node = \"$NODE_VERSION\""

# Trust the mise config (required for dynamically-created configs outside home)
mise trust "$WORKSPACE/.mise.toml" >&2

# Add mise shims to PATH for this script
export PATH="/home/node/.local/share/mise/shims:$PATH"

log "Running mise install..."
(cd "$WORKSPACE" && mise install 2>&1 | grep -v "^$" >&2) || {
  log "ERROR: mise install failed"
  exit 4
}

# --- Step 7: Detect package manager ---
detect_package_manager() {
  local workspace="$1"

  # Priority 1: packageManager field in package.json (corepack standard)
  if [ -f "$workspace/package.json" ]; then
    local pm_field
    pm_field=$(python3 -c "
import json, sys
try:
    pkg = json.load(open(sys.argv[1], encoding='utf-8'))
    pm = pkg.get('packageManager', '')
    if pm:
        print(pm.split('@')[0])
except Exception:
    pass
" "$workspace/package.json" 2>/dev/null)
    if [ -n "$pm_field" ]; then
      log "Found packageManager field: $pm_field"
      echo "$pm_field"
      return
    fi
  fi

  # Priority 2: Lockfile detection
  if [ -f "$workspace/pnpm-lock.yaml" ]; then
    echo "pnpm"
  elif [ -f "$workspace/yarn.lock" ]; then
    echo "yarn"
  elif [ -f "$workspace/package-lock.json" ]; then
    echo "npm"
  else
    echo "npm"  # Default fallback
  fi
}

PACKAGE_MANAGER=$(detect_package_manager "$WORKSPACE")
log "Package manager: $PACKAGE_MANAGER"

# --- Step 8: Install dependencies ---
if [ -f "$WORKSPACE/package.json" ]; then
  # Validate package manager before subshell (subshell assignments don't propagate)
  case "$PACKAGE_MANAGER" in
    pnpm|yarn|npm) ;;
    *)
      log "WARNING: Unknown package manager '$PACKAGE_MANAGER' — using npm"
      PACKAGE_MANAGER="npm"
      ;;
  esac

  log "Installing dependencies with $PACKAGE_MANAGER..."
  (
    cd "$WORKSPACE"

    case "$PACKAGE_MANAGER" in
      pnpm)
        pnpm install --frozen-lockfile 2>&1 || {
          log "WARNING: --frozen-lockfile failed, retrying without lock..."
          pnpm install 2>&1
        }
        ;;
      yarn)
        yarn install --frozen-lockfile 2>&1 || {
          log "WARNING: --frozen-lockfile failed, retrying without lock..."
          yarn install 2>&1
        }
        ;;
      npm)
        npm ci 2>&1 || {
          log "WARNING: npm ci failed, retrying with npm install..."
          npm install 2>&1
        }
        ;;
    esac
  ) >&2 || {
    log "ERROR: Dependency installation failed"
    exit 5
  }
  log "Dependencies installed successfully"
else
  log "No package.json found — skipping dependency installation"
  PACKAGE_MANAGER="none"
fi

# --- Step 9: Output JSON metadata (stdout only) ---
python3 -c "
import json, sys
print(json.dumps({
    'workspace': sys.argv[1],
    'node_version': sys.argv[2],
    'package_manager': sys.argv[3],
    'repo_name': sys.argv[4]
}))
" "$WORKSPACE" "$NODE_VERSION" "$PACKAGE_MANAGER" "$REPO_NAME"

log "Setup complete"
