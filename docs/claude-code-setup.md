# Claude Code Productivity Setup

A generic, cross-project setup for Claude Code inspired by [Boris Cherny's workflow](https://x.com/bcherny/status/2007179832300581177). Four layers: permissions, hooks, slash commands, and a verification feedback loop.

---

## Architecture

```
~/.claude/
├── settings.json          # Global permissions + hooks
├── CLAUDE.md              # Global instructions (already exists)
├── commands/              # Global slash commands
│   ├── simplify.md
│   ├── verify.md
│   └── review.md
└── hooks/
    └── verify.sh          # Polyglot build/lint/test script

<project>/.claude/
├── settings.json          # Project-specific permission overrides
└── commands/              # Project-specific slash commands
```

---

## Layer 1: Global Permissions

**File:** `~/.claude/settings.json`

Pre-allow safe, non-destructive commands globally so you aren't clicking "Allow" on every read operation.

```json
{
  "permissions": {
    "allow": [
      "Grep",
      "Glob",
      "Read",
      "Bash(git status*)",
      "Bash(git log*)",
      "Bash(git diff*)",
      "Bash(git branch*)",
      "Bash(which *)",
      "Bash(cat *)",
      "Bash(ls *)"
    ]
  }
}
```

Per-project `.claude/settings.json` can extend this with project-specific commands (e.g. `swift build`, `npm test`, `bq query`).

---

## Layer 2: Hooks

**File:** `~/.claude/settings.json` (merged with permissions above)

### PostToolUse — Auto-format after edits

Runs a formatter every time Claude writes or edits a file. Catches the last 10% of formatting issues before CI.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "command": "~/.claude/hooks/format.sh \"$CLAUDE_FILE_PATH\""
      }
    ]
  }
}
```

**File:** `~/.claude/hooks/format.sh`

```bash
#!/bin/bash
# Polyglot formatter — dispatches by file extension
FILE="$1"
[ -z "$FILE" ] && exit 0

case "$FILE" in
  *.swift)     swiftformat --quiet "$FILE" 2>/dev/null ;;
  *.ts|*.tsx)  npx prettier --write "$FILE" 2>/dev/null ;;
  *.js|*.jsx)  npx prettier --write "$FILE" 2>/dev/null ;;
  *.py)        black --quiet "$FILE" 2>/dev/null ;;
  *.go)        gofmt -w "$FILE" 2>/dev/null ;;
  *.rs)        rustfmt "$FILE" 2>/dev/null ;;
esac
exit 0
```

### Stop — Verify before Claude declares "done"

Runs build/lint/test when Claude finishes. If the script exits non-zero, Claude sees the errors and keeps working.

```json
{
  "hooks": {
    "Stop": [
      {
        "command": "~/.claude/hooks/verify.sh"
      }
    ]
  }
}
```

**File:** `~/.claude/hooks/verify.sh`

```bash
#!/bin/bash
# Polyglot verification — detects project type and runs appropriate checks
# Returns non-zero if anything fails, which tells Claude to keep working

set -e

if [ -f "Package.swift" ] || [ -d "*.xcodeproj" ] || [ -d "*.xcworkspace" ]; then
    swift build 2>&1
    swiftlint lint --quiet 2>&1 || true
elif [ -f "package.json" ]; then
    npm run lint 2>&1
    npm test -- --watchAll=false 2>&1
elif [ -f "Cargo.toml" ]; then
    cargo check 2>&1
    cargo clippy -- -D warnings 2>&1
elif [ -f "go.mod" ]; then
    go build ./... 2>&1
    go vet ./... 2>&1
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
    python -m py_compile $(git diff --name-only -- '*.py') 2>&1
    ruff check . 2>&1 || true
fi
```

---

## Layer 3: Global Slash Commands

### `/simplify` — Code simplifier

**File:** `~/.claude/commands/simplify.md`

```markdown
Review all code changes in the current git diff (staged + unstaged). For each changed file:

1. Identify unnecessary complexity, duplication, or dead code introduced by the changes
2. Ensure pure functions are used for calculations — separate stateful operations from pure logic
3. Prefer Either/Result types for error handling over exceptions where the language supports it
4. Check that no unnecessary abstractions were added for one-time operations
5. Simplify without changing behavior
6. Run the project's build and linter after changes to confirm nothing broke
```

### `/verify` — Self-verification loop

**File:** `~/.claude/commands/verify.md`

```markdown
Verify your recent changes by running through this checklist. Do not stop until all steps pass:

1. Build the project — fix any compilation errors
2. Run the linter — fix any warnings or errors
3. Run tests related to the files you changed — fix any failures
4. If you made fixes in steps 1-3, go back to step 1 and re-verify
5. Report a final summary: what passed, what you fixed
```

### `/review` — Pre-PR code review

**File:** `~/.claude/commands/review.md`

```markdown
Act as a senior code reviewer on the diff between the current branch and main.
Run: git diff main...HEAD

Review for:
1. Bugs, logic errors, and edge cases
2. Security issues (injection, auth, data exposure)
3. Style and convention violations relative to surrounding code
4. Missing error handling at system boundaries
5. Code that should have tests but doesn't

Output a structured review with severity levels: 🔴 must-fix, 🟡 should-fix, 🟢 nit.
```

---

## Layer 4: Combined settings.json

The full `~/.claude/settings.json` combining all layers:

```json
{
  "permissions": {
    "allow": [
      "Grep",
      "Glob",
      "Read",
      "Bash(git status*)",
      "Bash(git log*)",
      "Bash(git diff*)",
      "Bash(git branch*)",
      "Bash(which *)",
      "Bash(cat *)",
      "Bash(ls *)"
    ]
  },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "command": "~/.claude/hooks/format.sh \"$CLAUDE_FILE_PATH\""
      }
    ],
    "Stop": [
      {
        "command": "~/.claude/hooks/verify.sh"
      }
    ]
  }
}
```

---

## Quick Start

Use the prompt below to have Claude Code set this up for you:

---

### Setup Prompt

```
Set up my Claude Code productivity environment with:

1. Update ~/.claude/settings.json with:
   - Global permissions for safe read-only commands (Grep, Glob, Read, git status/log/diff/branch, which, cat, ls)
   - A PostToolUse hook that runs ~/.claude/hooks/format.sh on Edit|Write operations
   - A Stop hook that runs ~/.claude/hooks/verify.sh
   - Preserve any existing settings (model, plugins, etc.)

2. Create ~/.claude/hooks/format.sh (chmod +x):
   - Polyglot formatter that dispatches by file extension
   - Swift → swiftformat, TS/JS → prettier, Python → black, Go → gofmt, Rust → rustfmt
   - Always exit 0 (formatting failures shouldn't block)

3. Create ~/.claude/hooks/verify.sh (chmod +x):
   - Detect project type from manifest files (Package.swift, package.json, Cargo.toml, go.mod, pyproject.toml)
   - Run build + lint for the detected type
   - Exit non-zero on failure so Claude keeps working

4. Create these global slash commands in ~/.claude/commands/:
   - simplify.md: Review git diff for unnecessary complexity, ensure pure functions for calculations, prefer Either/Result for errors, simplify without changing behavior, then build+lint
   - verify.md: Build → lint → test → loop until green → report summary
   - review.md: Review diff vs main for bugs, security, style, missing tests. Output with severity levels.

5. After creating everything, verify the setup by:
   - Checking that settings.json is valid JSON
   - Checking that hook scripts are executable
   - Listing the created commands
```

---

## Notes

- **Project-specific overrides**: Add a `<project>/.claude/settings.json` to extend permissions for that project (e.g. `Bash(swift build*)`, `Bash(npm test*)`).
- **Project-specific commands**: Add a `<project>/.claude/commands/` directory for project-specific slash commands.
- **Team sharing**: Check `.claude/settings.json`, `.claude/commands/`, and `CLAUDE.md` into version control so the whole team benefits.
- **The key principle**: Give Claude a verification feedback loop. The Stop hook + `/verify` command are the highest-value additions — they 2-3x output quality by letting Claude self-correct.
