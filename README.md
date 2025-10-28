# Aizen

A macOS developer tool for managing Git worktrees with integrated terminal and AI agent support.

## Features

- **Workspace Management**: Organize repositories into workspaces
- **Git Worktree Support**: Create and manage Git worktrees with visual UI
- **Integrated Terminal**: GPU-accelerated terminal with libghostty
- **AI Agent Integration**: Support for Claude, Codex, and Gemini via Agent Client Protocol (ACP)
- **Markdown Rendering**: View and render markdown content
- **Syntax Highlighting**: Code highlighting with HighlightSwift

## Requirements

- macOS 26.0+
- Xcode 16.0+
- Swift 5.0+

## Dependencies

- [libghostty](https://github.com/ghostty-org/ghostty) - GPU-accelerated terminal emulator
- [swift-markdown](https://github.com/apple/swift-markdown) - Markdown parsing
- [HighlightSwift](https://github.com/appstefan/highlightswift) - Syntax highlighting

## Installation

1. Clone the repository with Git LFS support:
   ```bash
   git lfs install
   git clone https://github.com/vivy-company/aizen.git
   ```
2. Open `aizen.xcodeproj` in Xcode
3. Build and run

## Configuration

### Terminal Settings

Configure terminal appearance in Settings:
- Font and size
- Color themes (Catppuccin, Dracula, Nord, Gruvbox, TokyoNight, etc.)
- Custom color palettes

### AI Agents

Set up AI agents in Settings > Agents:
- Claude: Install and configure path
- Codex: Install and configure path
- Gemini: Install and configure path

### Editor

Configure default code editor in Settings > General:
- VS Code (`code`)
- Cursor (`cursor`)
- Sublime Text (`subl`)

## Usage

1. Create a workspace
2. Add Git repositories
3. Create worktrees for different branches
4. Open terminals in worktree directories
5. Use AI agents for code assistance

## Keyboard Shortcuts

- `⌘ D` - Split terminal right
- `⌘ ⇧ D` - Split terminal down
- `⌘ W` - Close terminal pane
- `⇧ ⇥` - Cycle chat mode

## Development

### Project Structure

The codebase is organized by domain for better maintainability and scalability:

```
aizen/
├── App/
│   └── aizenApp.swift                    # App entry point and window management
│
├── Models/
│   └── ACP/
│       └── ACPTypes.swift                # Agent Client Protocol type definitions
│
├── Services/
│   ├── Agent/
│   │   ├── ACPClient.swift               # ACP subprocess communication
│   │   ├── AgentSession.swift            # Agent session state management
│   │   ├── AgentRegistry.swift           # Agent discovery and configuration
│   │   ├── AgentInstaller.swift          # Agent installation logic
│   │   └── AgentRouter.swift             # Agent request routing
│   ├── Git/
│   │   ├── GitService.swift              # Git command execution
│   │   └── RepositoryManager.swift       # Repository and worktree management
│   ├── Persistence/
│   │   └── Persistence.swift             # Core Data stack
│   └── AppDetector.swift                 # Installed app discovery
│
├── Views/
│   ├── ContentView.swift                 # Main navigation layout
│   ├── Settings/
│   │   ├── SettingsView.swift            # Settings container
│   │   ├── GeneralSettingsView.swift     # Editor preferences
│   │   ├── TerminalSettingsView.swift    # Terminal configuration
│   │   └── AgentsSettingsView.swift      # Agent setup
│   ├── Workspace/
│   │   ├── WorkspaceSidebarView.swift    # Workspace list sidebar
│   │   ├── WorkspaceCreateSheet.swift    # Workspace creation
│   │   └── WorkspaceEditSheet.swift      # Workspace editing
│   ├── Worktree/
│   │   ├── WorktreeListView.swift        # Worktree list
│   │   ├── WorktreeDetailView.swift      # Worktree details and actions
│   │   ├── WorktreeCreateSheet.swift     # Worktree creation
│   │   └── RepositoryAddSheet.swift      # Repository addition
│   ├── Chat/
│   │   ├── ChatTabView.swift             # Chat tab management
│   │   ├── ChatSessionView.swift         # Chat session interface
│   │   ├── MessageBubbleView.swift       # Message rendering
│   │   ├── ToolCallView.swift            # Tool execution status
│   │   ├── AgentIconView.swift           # Agent icon component
│   │   ├── ACPContentViews.swift         # ACP content rendering
│   │   └── Components/
│   │       ├── ChatInputView.swift       # Chat input field
│   │       ├── MarkdownContentView.swift # Markdown rendering
│   │       ├── CodeBlockView.swift       # Code block with syntax highlighting
│   │       └── ContentBlockView.swift    # Multi-type content blocks
│   └── Terminal/
│       ├── TerminalTabView.swift         # Terminal tab management
│       └── TerminalSplitLayout.swift     # Terminal pane splitting
│
├── Managers/
│   └── ChatSessionManager.swift          # Chat session lifecycle
│
└── Utilities/
    ├── LanguageDetection.swift           # Code language detection
    └── WorkspaceNameGenerator.swift      # Random workspace names
```

### Architecture

- **MVVM Pattern**: Views observe `@ObservableObject` models
- **Actor Model**: Thread-safe concurrent operations (`ACPClient`, `GitService`)
- **Core Data**: Persistent storage for workspaces, repositories, worktrees
- **SwiftUI**: Declarative UI with modern Swift concurrency (async/await)

## License

Copyright © 2025
