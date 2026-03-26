#!/usr/bin/env bash
# auto-review-hook.sh — Auto-review every code change with a second AI model
#
# Claude Code PostToolUse hook that triggers Codex (GPT) to review
# every file you edit. Different model family = different blindspots.
#
# Setup:
#   1. Install Codex CLI: npm install -g @openai/codex
#   2. Auth: codex auth login
#   3. Add to Claude Code settings (see README)
#
# Receives JSON on stdin from Claude Code:
# {"tool_name":"Edit","tool_input":{"file_path":"/path/to/file"},...}

set -uo pipefail

REVIEWS_DIR="${REVIEWS_DIR:-$HOME/.ai-reviews}"
mkdir -p "$REVIEWS_DIR"

# Extract file path from stdin JSON
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)

# Skip if no file path or file doesn't exist
[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

# Skip non-code files
case "$FILE_PATH" in
  *.md|*.txt|*.json|*.plist|*.log|*.csv|*.env|*.gitignore) exit 0 ;;
  *node_modules*|*/.git/*) exit 0 ;;
esac

# Skip tiny or huge files
LINE_COUNT=$(wc -l < "$FILE_PATH" 2>/dev/null | tr -d ' ')
[[ "$LINE_COUNT" -lt 5 || "$LINE_COUNT" -gt 500 ]] && exit 0

# Deduplicate: skip if reviewed in the last 60 seconds
DEDUP_FILE="$REVIEWS_DIR/.last-reviewed"
NOW=$(date +%s)
if [[ -f "$DEDUP_FILE" ]]; then
  LAST_TIME=$(grep -F "$FILE_PATH" "$DEDUP_FILE" 2>/dev/null | tail -1 | cut -d'|' -f1)
  if [[ -n "$LAST_TIME" ]] && (( NOW - LAST_TIME < 60 )); then
    exit 0
  fi
fi
echo "${NOW}|${FILE_PATH}" >> "$DEDUP_FILE"

# Run review in background (non-blocking)
TIMESTAMP=$(date -u '+%Y%m%dT%H%M%SZ')
BASENAME=$(basename "$FILE_PATH")
REVIEW_FILE="$REVIEWS_DIR/${TIMESTAMP}-${BASENAME}.md"

(
  # Get diff if in a git repo, otherwise review full file
  FILE_DIFF=""
  FILE_DIR=$(dirname "$FILE_PATH")
  if git -C "$FILE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    FILE_DIFF=$(git -C "$FILE_DIR" diff HEAD -- "$FILE_PATH" 2>/dev/null)
    [[ -z "$FILE_DIFF" ]] && FILE_DIFF=$(git -C "$FILE_DIR" diff HEAD~1 HEAD -- "$FILE_PATH" 2>/dev/null)
  fi

  if [[ -n "$FILE_DIFF" ]]; then
    REVIEW_CONTEXT="DIFF (review ONLY the changed lines):

$FILE_DIFF"
  else
    REVIEW_CONTEXT="FULL FILE:

$(cat "$FILE_PATH")"
  fi

  REVIEW_OUTPUT=$(codex exec \
    --ephemeral \
    --skip-git-repo-check \
    -o /dev/stdout \
    "You are a security-focused code reviewer. Review ONLY this file for:
1. Security vulnerabilities (injection, leaks, auth bypass)
2. Error handling gaps (uncaught exceptions, missing validation)
3. Resource leaks (unclosed connections, missing cleanup)
4. Logic bugs (off-by-one, race conditions, null derefs)

RULES:
- Focus on the DIFF if provided — what changed, not the entire file.
- If no issues found, respond with: NO_ISSUES_FOUND with brief rationale.
- Every finding must have: Severity (P0-P3), Line, Finding, Fix.

File: $FILE_PATH

$REVIEW_CONTEXT" 2>/dev/null)

  # Save review
  {
    echo "# Auto-Review: $BASENAME"
    echo "**File:** $FILE_PATH"
    echo "**Time:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""
    echo "$REVIEW_OUTPUT"
  } > "$REVIEW_FILE"

) &

exit 0
