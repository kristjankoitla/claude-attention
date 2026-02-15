# Claude Notification

A macOS menu bar indicator for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows how many terminal sessions are waiting for your input.

## Table of Contents

- [Introduction](#introduction)
- [What Exactly Does It Do](#what-exactly-does-it-do)
- [Install & Uninstall](#install--uninstall)
  - [Prerequisites](#prerequisites)
  - [Install](#install)
  - [Uninstall](#uninstall)
  - [Files Modified Outside This Repository](#files-modified-outside-this-repository)
- [How It's Implemented](#how-its-implemented)
  - [Architecture](#architecture)
  - [Hook Lifecycle](#hook-lifecycle)
  - [Session Files](#session-files)
  - [Cleanup](#cleanup)
  - [Single Instance Lock](#single-instance-lock)
  - [Menu Bar Icon](#menu-bar-icon)

## Introduction

If you run multiple Claude Code sessions across different terminals, there's no built-in way to know which ones are waiting for you. You end up cycling through tabs to check.

Claude Notification solves this with a single icon in your menu bar. A sparkle shows up when any session needs attention, with a Roman numeral count inside it. When you respond, the count goes back down. At a glance, you know whether anything is waiting.

It installs in one command, starts automatically on login, and removes cleanly.

## What Exactly Does It Do

The tool has two halves:

1. **Shell hooks** that Claude Code calls automatically when events happen (response finished, permission needed, user replied). These create and delete small files in a shared directory — one file per session that needs attention.

2. **A menu bar app** (compiled Swift) that watches that directory and renders a count in the macOS status bar.

The icon has three states:

| State | Icon | Meaning |
|-------|------|---------|
| Idle | Thin 4-pointed sparkle | No sessions need input |
| Attention | Fat sparkle with Roman numeral (I, II, III, ...) | N sessions are waiting |
| Transition | Rotating, morphing sparkle | Animating between states (~0.67s) |

When you click the icon, a dropdown shows the status in plain text and a Quit option.

## Install & Uninstall

### Prerequisites

- macOS
- Xcode Command Line Tools — `xcode-select --install`
- Python 3 (included with Xcode CLT)
- Claude Code

### Install

```
./install/install.sh
```

One command. No manual configuration. The installer:

1. **Creates directories** — `~/.claude-notification/{bin,hooks,scripts,sessions}`
2. **Copies hook scripts** — `signal-attention.sh` and `clear-attention.sh` into the hooks directory
3. **Compiles the Swift app** — builds `sources/` into a single binary at `~/.claude-notification/bin/claude-notification`, then restricts it to owner-only access and ad-hoc codesigns it
4. **Configures Claude Code** — adds hook entries to `~/.claude/settings.json` (existing settings are preserved)
5. **Sets up auto-start** — creates a LaunchAgent at `~/Library/LaunchAgents/com.claude.notification.plist` and starts the app immediately

### Uninstall

```
./install/uninstall.sh
```

Stops the app, removes the hooks from Claude Code settings, deletes the LaunchAgent, and removes `~/.claude-notification/`. Leaves no traces.

### Files Modified Outside This Repository

| File | Change | Reverted on uninstall |
|------|--------|-----------------------|
| `~/.claude/settings.json` | Adds hook entries for 5 Claude Code events | Yes |
| `~/Library/LaunchAgents/com.claude.notification.plist` | LaunchAgent for auto-start | Yes (deleted) |
| `~/.claude-notification/` | Installation directory | Yes (deleted) |

## How It's Implemented

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Claude Code (terminal)                                  │
│                                                         │
│  Event fires ──► Hook script runs                       │
│                    │                                    │
│                    ├─ signal-attention.sh                │
│                    │    Creates session file             │
│                    │                                    │
│                    └─ clear-attention.sh                 │
│                         Deletes session file             │
└────────────────────────┬────────────────────────────────┘
                         │ filesystem
                         ▼
┌─────────────────────────────────────────────────────────┐
│ ~/.claude-notification/sessions/                        │
│                                                         │
│  <session-id-1>    ← "12345:1707000000"                 │
│  <session-id-2>    ← "12400:1707000010"                 │
└────────────────────────┬────────────────────────────────┘
                         │ DispatchSource (filesystem watch)
                         ▼
┌─────────────────────────────────────────────────────────┐
│ Menu bar app (Swift)                                    │
│                                                         │
│  SessionMonitor ──► count files ──► AnimationController  │
│                                          │              │
│  Cleanup timer                    IconRenderer           │
│  (every 10s)                      SparkleShape           │
│                                   GlyphPath              │
│                                          │              │
│                                          ▼              │
│                                    NSStatusBar icon      │
└─────────────────────────────────────────────────────────┘
```

The project has no external dependencies. The Swift app uses only AppKit, Foundation, and CoreText. The hooks use only standard POSIX tools. The installer uses Python 3 (stdlib only) for JSON manipulation and template rendering.

**Source layout:**

```
hooks/
  common.sh                  Shared setup: read stdin, extract and sanitize session_id
  signal-attention.sh        Create a session file (Stop, PermissionRequest)
  clear-attention.sh         Delete a session file (UserPromptSubmit, PostToolUse, SessionEnd)

sources/
  main.swift                  Entry point — NSApplication in accessory mode
  AppDelegate.swift           Lifecycle — start/stop the controller
  Constants.swift             Icon size, animation timing, cleanup interval

  controllers/
    StatusBarController.swift  Menu bar item, state management, menu delegate
    AnimationController.swift  Smoothstep transition between idle/attention icons

  monitoring/
    SessionMonitor.swift       Orchestrator — wires sub-components together
    SessionStore.swift          Session file I/O, staleness logic, cleanup
    DirectoryMonitor.swift      Filesystem watcher with retry/backoff
    ProcessWatcher.swift        PID exit watcher via kqueue
    ProcessLock.swift           flock-based single-instance lock

  rendering/
    IconRenderer.swift          Compose sparkle + glyph into menu bar icons
    SparkleShape.swift          4-pointed star geometry
    GlyphPath.swift             CoreText text-to-outline conversion

install/
  install.sh                   Install script — compile, configure hooks, set up LaunchAgent
  uninstall.sh                 Uninstall script — stop app, remove hooks, delete files
  scripts/
    preflight.sh               Pre-install checks (macOS, swiftc, python3)
    require_macos.sh            Platform guard
    settings_utils.py           Atomic JSON read/write for ~/.claude/settings.json
    configure_hooks.py          Add hook entries to Claude Code settings
    remove_hooks.py             Remove hook entries from Claude Code settings
    render_template.py          Substitute placeholders in the LaunchAgent plist template
  resources/
    Info.plist                   App bundle metadata (LSUIElement for menu-bar-only)
    LaunchAgent.plist            Template for the launchd plist
```

### Hook Lifecycle

Five Claude Code events are hooked:

| Event | Script | Effect |
|-------|--------|--------|
| `Stop` | `signal-attention.sh` | Claude finished responding — needs input |
| `PermissionRequest` | `signal-attention.sh` | Claude needs tool permission |
| `PostToolUse` | `clear-attention.sh` | Tool executed — permission was handled |
| `UserPromptSubmit` | `clear-attention.sh` | User sent a prompt |
| `SessionEnd` | `clear-attention.sh` | Session closed |

A typical flow:

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

With multiple terminals, each session independently manages its own file. The counter reflects the total across all sessions.

### Session Files

Each session file lives at `~/.claude-notification/sessions/<session-id>` and contains:

```
<pid>:<unix-timestamp>
```

- **pid** — the Claude Code (Node) process ID, found by walking up the process tree from the hook script. Used to detect dead sessions.
- **timestamp** — when the attention signal was created. Used for staleness checks.

Session IDs are sanitized to `[a-zA-Z0-9_-]` only, preventing path traversal. Files are created atomically via `mktemp` + `mv`. The session directory has mode `700` and hooks run with `umask 077`.

### Cleanup

The menu bar app runs a cleanup timer every 10 seconds. A session file is removed if any of these are true:

1. **Dead process** — the PID in the file no longer exists (`kill(pid, 0)` returns `ESRCH`)
2. **Stale timestamp** — the timestamp in the file is older than 15 minutes
3. **Old file fallback** — the file's modification date is older than 15 minutes (covers files with missing or unparseable content)

### Single Instance Lock

The app acquires an exclusive non-blocking file lock (`flock(LOCK_EX | LOCK_NB)`) on `~/.claude-notification/.lock` at startup. If another instance is already running, the new one logs a message and exits immediately.

### Menu Bar Icon

The icon is an 18x18 template image (adapts to light/dark mode automatically):

- **Idle**: a 4-pointed sparkle with thin inner points (`innerRatio: 0.35`)
- **Attention**: a fatter sparkle (`innerRatio: 0.65`) with a Roman numeral glyph cut out of the center using even-odd fill. Counts above 10 display as "X+".
- **Transition**: 40 frames over ~0.67 seconds. The sparkle rotates 180 degrees and morphs between the two shapes using smoothstep interpolation (`t * t * (3 - 2t)`).

The numeral is rendered as glyph outlines via CoreText (`CTFontCreatePathForGlyph`), not as text, so it scales cleanly and can be subtracted from the sparkle shape.
