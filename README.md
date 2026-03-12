# Aizen

[English](README.md) | [简体中文](README.zh-CN.md)

[![macOS](https://img.shields.io/badge/macOS-13.5+-black?style=flat-square&logo=apple)](https://aizen.win)
[![Swift](https://img.shields.io/badge/Swift-5.0+-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/License-GPL%203.0-blue?style=flat-square)](LICENSE)
[![Discord](https://img.shields.io/badge/-Discord-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/zemMZtrkSb)
[![Twitter](https://img.shields.io/badge/-Twitter-1DA1F2?style=flat-square&logo=x&logoColor=white)](https://x.com/aizenwin)
[![Sponsor](https://img.shields.io/badge/-Sponsor-ff69b4?style=flat-square&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/vivy-company)

> **Early Access** — Aizen is under active development with near-daily updates. Expect breaking changes and new features frequently.

A native macOS workspace for developers working across multiple repos and branches at once.

Bring order to your repos. Switch worktrees, not windows.

![Aizen Demo](https://r2.aizen.win/demo.png)

## What is Aizen?

Aizen is a worktree-first developer workspace for macOS. It keeps the tools that usually spill across separate apps attached to each worktree: terminal, files, browser, agent chat, Git context, and review state.

## Current Highlights

### Worktree-first workspace
- **Workspaces** — Organize repositories into color-coded groups
- **Worktrees** — Create and manage Git worktrees with visual UI
- **Per-worktree sessions** — Each worktree has its own terminal, files, browser, and chat

### Terminal and CLI
- **GPU-accelerated** — Powered by [libghostty](https://github.com/ghostty-org/ghostty)
- **Split panes and tabs** — Horizontal and vertical splits with presets and themes
- **Persistence** — Optional tmux-backed terminal session restore
- **CLI companion** — Open repos, manage workspaces, and attach to persistent terminals with `aizen`

### Agents and MCP
- **ACP registry-first** — Add registry agents or bring your own custom command/binary
- **Supported agents** — Works with Claude Code, Codex, OpenCode, Gemini, and other ACP-compatible agents
- **MCP marketplace** — Browse and add MCP servers from inside the app
- **Rich input** — File attachments, tool calls, and on-device voice input with waveform visualization

### Git, Review, and Delivery
- **Git operations** — Stage, commit, push, pull, merge, and branch from the UI
- **Diff and review** — Syntax-highlighted diffs, review comments, and PR/MR detail views
- **Workflow visibility** — GitHub Actions and GitLab CI runs from the worktree sidebar
- **Apple workflows** — Xcode build integration for `.xcodeproj` and `.xcworkspace` projects

### Files and Browser
- **File browser** — Tree view, search, syntax highlighting, inline diffs, and multiple tabs
- **Built-in browser** — Per-worktree tabs for docs, previews, auth flows, and local apps

## Requirements

- macOS 13.5+
- Apple Silicon or Intel Mac

## Installation

Download from [aizen.win](https://aizen.win)

Signed and notarized with an Apple Developer certificate.

## Build from Source

- Xcode 16.0+
- Swift 5.0+
- Git LFS
- Zig (for building libghostty): `brew install zig`

```bash
git lfs install
git clone https://github.com/vivy-company/aizen.git
cd aizen

# Build libghostty (universal arm64 + x86_64)
./scripts/build-libghostty.sh

# Open in Xcode and build
open aizen.xcodeproj
```

To rebuild libghostty at a specific commit:
```bash
./scripts/build-libghostty.sh <commit-sha>
```

## Agent Setup

Aizen now uses ACP registry agents as the default path.

- Seeded defaults include Claude Code, Codex, and OpenCode
- Add more agents from **Settings > Agents**
- Bring your own custom agent with a command or executable path
- Add MCP servers per agent from the built-in marketplace

## CLI

Install the bundled CLI from **Settings > General**, then use commands like:

```bash
aizen open .
aizen workspace list
aizen terminal . --attach
aizen attach
```

The CLI can add or open repositories, inspect tracked workspaces, create persistent terminals, and attach to tmux-backed sessions created in the app.

## Configuration

### Terminal

Settings > Terminal:
- Font family and size
- Color themes and presets
- Voice input button
- tmux session persistence

### General

Settings > General:
- Default external editor (VS Code, Cursor, Sublime Text)
- CLI install and status
- Optional Xcode build button for Apple projects

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘ D` | Split terminal right |
| `⌘ ⇧ D` | Split terminal down |
| `⌘ W` | Close pane |
| `⌘ T` | New tab |
| `⇧ ⇥` | Cycle chat mode |
| `ESC` | Interrupt agent |

## Dependencies

- [libghostty](https://github.com/ghostty-org/ghostty) — Terminal emulator
- [libgit2](https://libgit2.org/) — Native Git operations
- [VVDevKit](https://github.com/vivy-company/VVDevKit) — Editor/markdown/timeline/diff + Tree-sitter highlighting
- [Sparkle](https://github.com/sparkle-project/Sparkle) — Auto-updates

## Architecture

```
aizen/
├── App/                    # Entry point
├── Models/                 # Data models, ACP, Git, MCP, Tab, Terminal
├── Services/
│   ├── Agent/              # ACP client, registry, installers, session management
│   ├── Git/                # Worktree, branch, staging, diff, review, hosting
│   ├── Audio/              # Voice recording, transcription
│   ├── MCP/                # MCP server management
│   ├── Workflow/           # GitHub Actions / GitLab CI integration
│   ├── Xcode/              # Xcode build and device integration
│   └── Highlighting/       # Tree-sitter integration
├── Views/
│   ├── Chat/               # Sessions, input, markdown, tool calls
│   ├── Worktree/           # List, detail, Git, workflow, review
│   ├── Terminal/           # Tabs, split layout, panes
│   ├── Files/              # Tree view, content tabs
│   ├── Browser/            # Tabs, controls
│   ├── Search/             # Search UI
│   ├── CommandPalette/     # Command palette
│   └── Settings/           # Settings panels and installers
├── GhosttyTerminal/        # libghostty wrapper
├── Managers/               # Shared state managers
└── Utilities/              # Helpers
```

**Patterns:**
- MVVM with observable models
- Actor-based services for concurrency-sensitive work
- Core Data for persistence
- SwiftUI + async/await + `AsyncStream`

## License

GNU General Public License v3.0

Copyright © 2026 Vivy Technologies Co., Limited
