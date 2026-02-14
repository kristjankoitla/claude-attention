# Claude Notification

A macOS menu bar plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows how many terminal sessions are waiting for your input.

When Claude finishes a response or needs permission to use a tool, a counter appears in your menu bar. When you respond, the counter goes back down. This lets you run multiple Claude Code sessions across different terminals and know at a glance which ones need attention — without checking each tab.

## How it works

The plugin has two parts:

1. **Menu bar app** — A compiled Swift binary that watches a directory and displays a count in the macOS status bar.
2. **Shell hooks** — Bash scripts triggered by Claude Code's hook system that create and remove files in that directory.

Each Claude Code session gets a file in `~/.claude-notification/sessions/` when it needs attention. The menu bar app monitors that directory and displays the file count as a Roman numeral inside a sparkle icon. When no sessions need attention, it shows a plain sparkle.

## Prerequisites

- macOS
- Xcode Command Line Tools (`xcode-select --install`)
- Python 3 (included with Xcode CLT)
- Claude Code

## Install

```
./install.sh
```

This single command does everything — no manual configuration needed.

## Uninstall

```
./uninstall.sh
```

Removes all installed files, the LaunchAgent, and the hooks from Claude Code settings. Leaves no traces.

## What the installer does

The installer performs five steps:

### 1. Create directories

```
~/.claude-notification/
├── bin/            # Compiled binary
├── hooks/          # Hook scripts
└── sessions/       # Session files (mode 700)
```

### 2. Install hook scripts

Copies `signal-attention.sh` and `clear-attention.sh` into `~/.claude-notification/hooks/` and makes them executable.

### 3. Compile the menu bar app

Compiles `ClaudeNotification.swift` into `~/.claude-notification/bin/claude-notification` using `swiftc`. Embeds an `Info.plist` with `LSUIElement=true` so the app runs as a menu bar–only agent (no Dock icon).

### 4. Configure Claude Code hooks

Adds hook entries to `~/.claude/settings.json`. If the file exists with other settings, they are preserved — only the notification hooks are added. If the file has invalid JSON, it is backed up before being replaced.

The following hooks are registered:

| Claude Code Event    | Script                | Effect                        |
|----------------------|-----------------------|-------------------------------|
| `Stop`               | `signal-attention.sh` | Claude finished — needs input |
| `PermissionRequest`  | `signal-attention.sh` | Claude needs permission       |
| `PostToolUse`        | `clear-attention.sh`  | Tool ran — permission handled |
| `UserPromptSubmit`   | `clear-attention.sh`  | User sent a prompt            |
| `SessionEnd`         | `clear-attention.sh`  | Session closed                |

### 5. Set up LaunchAgent

Creates a `launchd` plist at `~/Library/LaunchAgents/com.claude.notification.plist` so the menu bar app starts automatically on login. Stops any previously running instance before starting.

## Hook lifecycle

A typical session flows like this:

```
User sends prompt
  → UserPromptSubmit fires
  → clear-attention.sh removes session file
  → counter goes DOWN

Claude works, needs permission for a tool
  → PermissionRequest fires
  → signal-attention.sh creates session file
  → counter goes UP

User approves the permission
  → tool executes
  → PostToolUse fires
  → clear-attention.sh removes session file
  → counter goes DOWN

Claude finishes responding
  → Stop fires
  → signal-attention.sh creates session file
  → counter goes UP

User reads response and types next prompt
  → UserPromptSubmit fires
  → clear-attention.sh removes session file
  → counter goes DOWN
```

With multiple terminals, each session independently creates and removes its own file, so the counter reflects the total number of sessions that need attention at any moment.

## Session files

Each session file is stored at `~/.claude-notification/sessions/<session-id>` and contains:

```
<pid>:<unix-timestamp>
```

- **pid** — The Claude Code process ID (used by the cleanup timer to detect dead sessions)
- **timestamp** — When the attention signal was created (used for staleness checks)

Session IDs are sanitized to `[a-zA-Z0-9_-]` to prevent path traversal.

## Cleanup

The menu bar app runs a cleanup timer every 10 seconds that removes stale session files:

1. **Dead process** — If the PID in the file no longer exists (`kill -0` returns `ESRCH`), the file is removed.
2. **Stale timestamp** — If the timestamp in the file is older than 15 minutes, the file is removed.
3. **Old file fallback** — If the file's modification date is older than 15 minutes, the file is removed.

## Files modified outside this repository

| File | Change | Reverted on uninstall |
|------|--------|-----------------------|
| `~/.claude/settings.json` | Adds hook entries for 5 Claude Code events | Yes |
| `~/Library/LaunchAgents/com.claude.notification.plist` | Adds a LaunchAgent for auto-start | Yes (deleted) |
| `~/.claude-notification/` | Created as the installation directory | Yes (deleted) |

## Single instance

The app uses a file lock at `~/.claude-notification/.lock` with `flock(LOCK_EX | LOCK_NB)` to ensure only one instance runs at a time. If another instance is already running, the new one exits immediately.

## Menu bar icon

- **Idle** (no sessions waiting): A 4-pointed sparkle outline
- **Attention** (N sessions waiting): A fatter sparkle with a Roman numeral (I, II, III, ...) cut out of it
- **Transitions**: Animated over ~0.67 seconds with a smoothstep easing — the sparkle rotates and morphs between the idle and attention shapes
