# Auto-Review Hook

**Claude builds. Codex reviews. Every file. Automatically.**

A Claude Code hook that triggers OpenAI Codex to review every file you edit — in the background, non-blocking. Different model family catches different blindspots.

## How It Works

```
You edit a file in Claude Code
  → PostToolUse hook fires
    → Codex reviews just the git diff (not the whole file)
      → Findings saved to ~/.ai-reviews/
        → You keep working, uninterrupted
```

## Setup

### 1. Install Codex CLI
```bash
npm install -g @openai/codex
codex auth login
```

### 2. Add to Claude Code settings

Add to `~/.claude/settings.json`:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/auto-review-hook.sh",
            "timeout": 5,
            "async": true,
            "statusMessage": "Reviewing..."
          }
        ]
      }
    ]
  }
}
```

### 3. Done

Every Edit/Write triggers a background Codex review. Results saved to `~/.ai-reviews/`.

## What It Catches

- Security vulnerabilities (injection, leaks, auth bypass)
- Error handling gaps (uncaught exceptions, missing validation)
- Resource leaks (unclosed connections, missing cleanup)
- Logic bugs (off-by-one, race conditions, null derefs)

## Features

- **Diff-aware**: Reviews `git diff`, not the whole file
- **Non-blocking**: Runs in background, doesn't slow you down
- **Deduplication**: Won't re-review the same file within 60 seconds
- **Smart filtering**: Skips non-code files, tiny files, huge files

## Why Two Models?

Claude writes code with deep understanding but has blindspots. Codex catches patterns Claude misses — different training data, different architecture, different failure modes. This isn't redundancy. It's coverage.

## Requirements

- [Claude Code](https://claude.com/claude-code)
- [Codex CLI](https://github.com/openai/codex)
- `jq` (for JSON parsing)
- Git (for diff-aware reviews)

## License

MIT — Built by [MyndAIX](https://myndaix.com)
