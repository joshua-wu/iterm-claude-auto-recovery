# iTerm2 Claude Code Auto Recovery

Automatically resume your last Claude Code session when you reopen an iTerm2 tab.

## The Problem

Every time you close and reopen an iTerm2 tab, running `claude` starts a brand new session — your previous conversation context is lost. You have to manually use `claude --resume <session-id>` to get back to where you were.

## How It Works

This script wraps the `claude` command with a shell function that:

1. **Maps each iTerm2 tab to a Claude session** — using iTerm2's unique tab UUID (`ITERM_SESSION_ID`) as the key
2. **Auto-resumes** — when you type `claude` in a tab that previously had a session (same working directory), it automatically resumes that session
3. **Falls back gracefully** — in non-iTerm2 terminals, the `claude` command works exactly as before

The mapping is stored in `~/.claude/tab-sessions.json`.

## Features

- **Zero friction** — just type `claude` as usual, sessions are resumed automatically
- **Directory-aware** — only resumes if you're in the same directory as the original session
- **Session validation** — checks that the session file still exists before resuming
- **Override controls**:
  - `claude --new` — force a new session in the current tab
  - `claude --resume <id>` / `claude -r` / `claude -c` — manual session control (passed through as-is)
- **Debug tool** — run `claude-sessions` to inspect current tab-to-session mappings

## Prerequisites

- [iTerm2](https://iterm2.com/) (macOS terminal emulator)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- [jq](https://jqlang.github.io/jq/) — `brew install jq`

## Install / Uninstall with Claude

### Install

Copy the prompt below and paste it into Claude Code:

> Clone the repo https://github.com/joshua-wu/iterm-claude-auto-recovery to `~/.local/share/iterm-claude-auto-recovery`. Then detect my current shell (check `$SHELL`), and add `source ~/.local/share/iterm-claude-auto-recovery/iterm_claude_auto_recovery.sh` to my shell rc file (`~/.zshrc` for zsh, `~/.bashrc` for bash). Make sure not to add a duplicate line if it already exists. Verify with a syntax check on the rc file after editing.

### Uninstall

Copy the prompt below and paste it into Claude Code:

> Remove the line that sources `iterm_claude_auto_recovery.sh` from my shell rc file (check `$SHELL` to determine whether it's `~/.zshrc` or `~/.bashrc`). Also delete the directory `~/.local/share/iterm-claude-auto-recovery` and the mapping file `~/.claude/tab-sessions.json` if they exist. Verify with a syntax check on the rc file after editing.

## Manual Install

```bash
# 1. Clone the repo
git clone https://github.com/joshua-wu/iterm-claude-auto-recovery ~/.local/share/iterm-claude-auto-recovery

# 2. Add to your shell rc file

# For zsh (~/.zshrc):
echo 'source ~/.local/share/iterm-claude-auto-recovery/iterm_claude_auto_recovery.sh' >> ~/.zshrc

# For bash (~/.bashrc):
echo 'source ~/.local/share/iterm-claude-auto-recovery/iterm_claude_auto_recovery.sh' >> ~/.bashrc

# 3. Reload
source ~/.zshrc  # or source ~/.bashrc
```

## Manual Uninstall

```bash
# 1. Remove the source line from your rc file
#    Open ~/.zshrc (or ~/.bashrc) and delete the line:
#    source ~/.local/share/iterm-claude-auto-recovery/iterm_claude_auto_recovery.sh

# 2. Clean up
rm -rf ~/.local/share/iterm-claude-auto-recovery
rm -f ~/.claude/tab-sessions.json
```

## Usage

```bash
# Just use claude as normal — sessions auto-resume per tab
claude

# Force a brand new session in this tab
claude --new

# Inspect tab-session mappings
claude-sessions
```

## How the Mapping Works

```
iTerm2 Tab (UUID)  ──→  Claude Session ID + Working Directory
     ↓                           ↓
Tab reopened       ──→  Lookup mapping → validate session file
                                 ↓
                        Same dir + file exists → claude --resume <id>
                        Otherwise             → new session
```

## License

MIT
