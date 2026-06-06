#!/usr/bin/env bash
# Stop hook: after a turn completes, commit any changes, push to origin/main,
# verify there were no git errors, and confirm local matches remote.
# Outputs a JSON systemMessage so the result is visible in the UI.
set -uo pipefail

emit() { printf '{"systemMessage": %s}\n' "$(jq -Rs . <<<"$1")"; }

# Move to the repo root.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

changes="$(git status --porcelain)"
local_sha="$(git rev-parse HEAD 2>/dev/null || echo none)"
remote_sha="$(git rev-parse origin/main 2>/dev/null || echo none)"

# Nothing to commit and already in sync with main: stay silent.
if [ -z "$changes" ] && [ "$local_sha" = "$remote_sha" ]; then
  exit 0
fi

# Commit any pending changes.
if [ -n "$changes" ]; then
  git add -A
  if ! commit_out="$(git commit -m "Auto-commit: save changes from Claude Code session" 2>&1)"; then
    emit "Auto-commit FAILED:
$commit_out"
    exit 0
  fi
fi

# Push HEAD to main, retrying transient network failures (2s, 4s, 8s, 16s).
push_err=""
for delay in 0 2 4 8 16; do
  [ "$delay" -gt 0 ] && sleep "$delay"
  if push_out="$(git push origin HEAD:main 2>&1)"; then
    push_err=""
    break
  fi
  push_err="$push_out"
done

if [ -n "$push_err" ]; then
  emit "Auto-push to main FAILED:
$push_err"
  exit 0
fi

# Verify: fetch and confirm local HEAD matches origin/main.
git fetch origin main >/dev/null 2>&1
new_local="$(git rev-parse HEAD)"
new_remote="$(git rev-parse origin/main 2>/dev/null || echo none)"

if [ "$new_local" = "$new_remote" ]; then
  emit "Deployment confirmed: committed & pushed to main.
  commit:    ${new_local:0:7}
  origin/main matches local HEAD. No git errors."
else
  emit "Pushed to main but verification MISMATCH:
  local HEAD:  ${new_local:0:7}
  origin/main: ${new_remote:0:7}"
fi
exit 0
