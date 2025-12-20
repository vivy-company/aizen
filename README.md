# Aizen

[![macOS](https://img.shields.io/badge/macOS-13.5+-black?logo=apple)](https://aizen.win)
[![Swift](https://img.shields.io/badge/Swift-5.0+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue)](LICENSE)
[![Discord](https://img.shields.io/badge/Discord-Join-5865F2?logo=discord&logoColor=white)](https://discord.gg/eKW7GNesuS)
[![Twitter](https://img.shields.io/badge/Twitter-@aizenwin-1DA1F2?logo=x&logoColor=white)](https://x.com/aizenwin)

Bring order to your repos. Switch worktrees, not windows.

![Aizen Demo](https://r2.aizen.win/demo.png)

## What is Aizen?

Aizen is a macOS workspace for developers who work on multiple branches in parallel. Each worktree gets its own terminal, file browser, web browser, and agent session — so you switch worktrees, not windows.

## Features

### Core
- **Workspaces** — Organize repositories into color-coded groups
- **Worktrees** — Create and manage Git worktrees with visual UI
- **Per-worktree sessions** — Each worktree has its own terminal, files, browser, and chat

### Terminal
- **GPU-accelerated** — Powered by [libghostty](https://github.com/ghostty-org/ghostty)
- **Split panes** — Horizontal and vertical splits
- **Themes** — Catppuccin, Dracula, Nord, Gruvbox, TokyoNight, and more

### Agents
- **Supported** — Claude, Codex, Gemini, Kimi, and custom agents
- **Protocol** — Agent Client Protocol (ACP)
- **Auto-install** — From NPM or GitHub releases
- **Voice input** — On-device speech-to-text with waveform visualization

### Git
- **Operations** — Stage, commit, push, pull, merge, branch
- **Diff viewer** — Full-window diff with syntax highlighting
- **Status** — Real-time file status indicators

### File Browser
- **Tree view** — Hierarchical directory navigation
- **Syntax highlighting** — Tree-sitter for 50+ languages
- **Multi-tab** — Open multiple files

### Web Browser
- **Per-worktree** — Embedded browser for docs and previews
- **Multi-tab** — Session persistence

## Requirements

- macOS 13.5+
- Apple Silicon or Intel Mac

### Building from Source

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

## Installation

Download from [aizen.win](https://aizen.win)

Signed and notarized with an Apple Developer certificate.

## Configuration

### Agents

Settings > Agents:

| Agent | Install Method | Package |
|-------|---------------|---------|
| Claude | NPM | `@anthropic-ai/claude-code` |
| Codex | GitHub | `openai/codex` |
| Gemini | NPM | `@anthropic-ai/claude-code` |
| Kimi | GitHub | `MoonshotAI/kimi-cli` |

Agents can be auto-discovered and installed, or manually configured.

### Terminal

Settings > Terminal:
- Font family and size
- Color theme

### Editor

Settings > General:
- Default external editor (VS Code, Cursor, Sublime Text)

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
- [CodeEdit](https://github.com/CodeEditApp/CodeEdit) packages — Syntax highlighting (Tree-sitter)
- [Sparkle](https://github.com/sparkle-project/Sparkle) — Auto-updates

## Architecture

```
aizen/
├── App/                    # Entry point
├── Models/                 # Data models, ACP types
├── Services/
│   ├── Agent/              # ACP client, installers, session management
│   ├── Git/                # Worktree, branch, staging, diff services
│   ├── Audio/              # Voice recording, transcription
│   └── Highlighting/       # Tree-sitter integration
├── Views/
│   ├── Workspace/          # Sidebar, create/edit sheets
│   ├── Worktree/           # List, detail, git sidebar
│   ├── Terminal/           # Tabs, split layout, panes
│   ├── Chat/               # Sessions, input, markdown, tool calls
│   ├── Files/              # Tree view, content tabs
│   ├── Browser/            # Tabs, controls
│   └── Settings/           # All settings panels
├── GhosttyTerminal/        # libghostty wrapper
└── Utilities/              # Helpers
```

**Patterns:**
- MVVM with `@ObservableObject`
- Actor model for concurrency
- Core Data for persistence
- SwiftUI + async/await

## License

Apache License 2.0

Copyright © 2025 Vivy Technologies Co., Limited
