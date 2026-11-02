#!/usr/bin/env bash
set -u -o pipefail

AGENT="${AGENT:-plain-coder}"
TIMEOUT_CMD="$(command -v timeout || command -v gtimeout || true)"
if [[ -z "$TIMEOUT_CMD" ]]; then
  printf '%s\n' 'GNU timeout (timeout or gtimeout) is required but was not found.' >&2
  exit 1
fi

PROMPT=$(cat <<'PROMPT'
You are an autonomous TCG cheap roadmap executor.

Your job is to advance the codebase toward the product direction in PRODUCT.md without needing a human to pick the next task.

Orientation:
1. Inspect git status/diff and recent commits.
2. Read PRODUCT.md and DESIGN.md.
3. Reconcile them with recent commits and repository state.

Authority order:
1. Current code and tests.
2. PRODUCT.md.
3. Recent git history.

Task selection:
- Work on the highest-priority unfinished roadmap goal.
- Prefer unblocked, high-leverage correctness/playability work.
- Prefer work that removes blockers, improves validation, or clarifies unsupported states.
- Avoid repeating recent completed work.
- Treat stale recommendations as historical; explain why if bypassing them.
- If the top goal is blocked, do enabling work for it.
- Only move to later goals if earlier goals are complete, blocked, or the later task directly enables them.
- If all roadmap goals are complete, answer exactly DONE and make no changes.
- If work is impossible due missing services/data/credentials, explain BLOCKED with next steps.

Execution loop:
- Choose one meaningful batch.
- Implement it fully.
- Validate with relevant tests/tools.
- Continue within the batch until blocked or complete.
- A meaningful batch is one coherent mechanic slice, substantial bugfix, grouped UI/client improvement, or 3–5 related verified atomic changes.

Validation:
- Run the narrowest relevant tests first.
- Run broader checks before finishing when feasible.
- Use mix check when appropriate for completed code batches.
- For UI/play-surface changes, use browser/testing tools where relevant.

Git:
- Do not overwrite unrelated work.
- Stage only intended files.
- Commit once per completed batch with a conventional commit message.
PROMPT
)

LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/tcg-cheap-loop.XXXXXX")" || {
  printf '%s\n' 'Unable to create temporary log file.' >&2
  exit 1
}
cleanup() {
  rm -f -- "$LOG_FILE"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

for ((iteration = 1; iteration <= 150; iteration++)); do
  : >"$LOG_FILE"
  printf 'Starting iteration %d/150 with agent %s.\n' "$iteration" "$AGENT"

  env -u OPENCODE_SERVER_PASSWORD \
    OPENCODE_PERMISSION='{"*":"allow","bash":"allow","edit":"allow","external_directory":"allow","task":"allow","question":"deny"}' \
    "$TIMEOUT_CMD" --signal=TERM --kill-after=30s 45m \
    opencode run --auto --format default --agent "$AGENT" "$PROMPT" 2>&1 \
    | tee "$LOG_FILE"
  status=${PIPESTATUS[0]}

  if grep -Eq '^[[:space:]]*DONE[[:space:]]*$' "$LOG_FILE"; then
    printf '%s\n' 'DONE marker received; stopping successfully.'
    exit 0
  fi
  if grep -Eq '^[[:space:]]*BLOCKED([[:space:]:]|$)' "$LOG_FILE"; then
    printf '%s\n' 'BLOCKED marker received; stopping.' >&2
    exit 2
  fi

  if [[ "$status" -eq 124 || "$status" -eq 137 ]]; then
    printf '%s\n' 'OpenCode timed out; restarting from repository state.' >&2
  elif [[ "$status" -eq 0 ]]; then
    printf '%s\n' 'Batch completed; continuing.'
  else
    printf 'OpenCode exited with status %d; retrying.\n' "$status" >&2
  fi
  sleep 5
done

printf '%s\n' 'Iteration limit (150) reached.' >&2
exit 3
