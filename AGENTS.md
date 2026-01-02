# Aizen Project - Agent Instructions

## Project Overview

Aizen is a macOS developer tool for managing Git worktrees with integrated terminal, file browser, web browser, and AI agent support via the Agent Client Protocol (ACP).

## Architecture

### Domain Organization

```
aizen/
├── App/                    # Application entry point
├── Models/                 # Data models and protocol types (17 domains)
│   ├── ACP/                # ACP protocol types (11 files)
│   ├── Agent/              # Agent metadata and config
│   ├── Chat/               # Chat attachments
│   ├── Git/                # Git models (diff, merge, branch templates)
│   ├── MCP/                # Model Context Protocol types
│   ├── Tab/                # Tab state types
│   └── Terminal/           # Terminal preset config
├── Services/               # Business logic (17 service domains)
│   ├── Agent/              # ACP client, session, installers, delegates
│   ├── Git/                # Repository, libgit2, domain services
│   ├── Audio/              # Voice recording and speech recognition
│   ├── Highlighting/       # Tree-sitter syntax highlighting
│   ├── License/            # License management
│   ├── MCP/                # MCP server management
│   ├── Workflow/           # GitHub/GitLab CI/CD integration
│   └── Xcode/              # Xcode build and device management
├── Views/                  # SwiftUI views (18+ feature folders)
│   ├── Chat/               # Chat interface (18 files + 30 components)
│   ├── Worktree/           # Worktree management (12 files + 60 components)
│   ├── Terminal/           # Terminal views and split panes
│   ├── Files/              # File browser
│   ├── Browser/            # Web browser tabs
│   ├── Settings/           # Settings UI (8 primary + 15 components)
│   ├── Search/             # File search
│   └── CommandPalette/     # Spotlight-like command palette
├── GhosttyTerminal/        # GPU-accelerated terminal (15 files)
├── Managers/               # State managers (10 files)
├── Utilities/              # Helper functions (18 files)
├── Assets.xcassets/        # Icons and images
└── Resources/              # Shell integration, themes, terminfo
```

### Design Patterns

- MVVM: Views observe @ObservableObject models (e.g., AgentSession, ChatSessionViewModel).
- Actor model: Thread-safe services (ACPClient, Libgit2Service, XcodeBuildService).
- Delegation: Request handling (AgentFileSystemDelegate, AgentTerminalDelegate, AgentPermissionHandler).
- Domain services: Git operations split by domain (GitStatusService, GitBranchService, etc.).
- Core Data: 10 persistent entities with relationships.
- Modern concurrency: async/await, AsyncStream.

### Key Components

**Agent Client Protocol (ACP)**
- ACPClient (actor): Subprocess manager with JSON-RPC 2.0.
- ACPProcessManager: Process lifecycle management.
- ACPRequestRouter: Request/response routing.
- AgentSession (@MainActor): Observable session state wrapper.
- AgentInstaller: NPM, GitHub, Binary, UV installation methods.
- Supports Claude, Codex (OpenAI), and Gemini.

**Git Operations**
- RepositoryManager: CRUD for workspaces, repos, worktrees.
- Libgit2Service: Native libgit2 wrapper for git operations.
- Domain services: GitStatusService, GitBranchService, GitWorktreeService, GitDiffService, etc.
- GitDiffProvider + GitDiffCache: Diff fetching with caching.
- ReviewSessionManager: Code review sessions.

**Terminal Integration**
- GhosttyTerminalView: GPU-accelerated terminal with Metal rendering.
- Split pane support via TerminalSplitLayout.
- Terminal presets and session management.
- Shell integration with Ghostty resources.

**Chat Interface**
- ChatSessionView + ChatSessionViewModel: Full session UI.
- MessageBubbleView: Message rendering with markdown, code blocks.
- ToolCallView + ToolCallGroupView: Tool call visualization.
- Voice input with waveform visualization.
- File attachments and inline diffs.

**File Browser**
- FileBrowserSessionView: Tree view with file operations.
- FileContentView: File content display with syntax highlighting.

**CI/CD Integration**
- WorkflowSidebarView: GitHub Actions / GitLab CI display.
- WorkflowRunDetailView: Run details and logs.
- XcodeBuildManager: Xcode build integration.

## Development Guidelines

### When Working on Features

1. Respect domain boundaries:
   - Agent logic -> Services/Agent/
   - Git operations -> Services/Git/ (use domain services)
   - UI components -> Views/{feature}/
   - Terminal -> GhosttyTerminal/

2. Keep files focused:
   - Extract large views into components.
   - Split files over 500 lines when logical.
   - Put reusable components in Components/ folders.

3. Use modern Swift patterns:
   - Actors for concurrent operations.
   - @MainActor for UI state.
   - async/await over completion handlers.
   - AsyncStream for event streaming.

### File Organization Rules

- Place new agent-related code in Services/Agent/.
- Place new Git functionality in Services/Git/Domain/.
- Create new view folders when adding major features.
- Extract components to Components/ subfolder when reused 3+ times.
- Keep utilities generic in Utilities/.

### Protocol Communication

**ACP Flow**
1. User input -> ChatSessionView
2. -> ChatSessionViewModel.sendMessage(_:)
3. -> AgentSession.sendMessage(_:)
4. -> ACPClient.sendRequest(_:)
5. -> Subprocess (agent binary)
6. <- JSON-RPC notifications (streamed)
7. -> Delegates (AgentFileSystemDelegate, AgentTerminalDelegate)
8. -> Published state updates
9. -> SwiftUI view refreshes

### Common Tasks

**Add new agent support**
1. Update AgentRegistry.swift with agent config.
2. Add icon to Assets.xcassets/AgentIcons.xcassetcatalog/.
3. Update AgentIconView.swift for icon mapping.
4. Add installer in Services/Agent/Installers/ if needed.

**Add new Git domain operation**
1. Create service in Services/Git/Domain/ (e.g., GitNewFeatureService.swift).
2. Add methods following existing patterns.
3. Integrate with Libgit2Service or shell commands as needed.

**Modify ACP protocol**
1. Update types in Models/ACP/ (split across multiple files).
2. Handle in ACPClient or appropriate delegate.
3. Update AgentSession if state changes needed.
4. Update UI in relevant view.

### Dependencies

- libghostty: GPU-accelerated terminal with Metal.
- libgit2: Native git operations.
- swift-markdown: Markdown parsing (Apple official).
- HighlightSwift: Syntax highlighting (highlight.js wrapper).
- CodeEdit packages: Tree-sitter syntax highlighting.
- Sparkle: Auto-update framework.

### Build Notes

- Minimum: macOS 13.5+.
- Xcode 16.0+.
- Swift 5.0+.
- All file paths must be absolute in tool operations.
- Use git mv for file moves to preserve history.
- Deep linking via aizen:// URL scheme.

## Core Data Schema

**Entities**
- Workspace -> Many Repository -> Many Worktree.
- Worktree -> TerminalSession, ChatSession, FileBrowserSession, BrowserSession.
- ChatSession -> Many ChatMessage -> Many ToolCallRecord.

## Code Style

- Use Swift naming conventions (camelCase, PascalCase for types).
- Prefer explicit types for clarity in complex code.
- Add comments for non-obvious logic, especially in ACP protocol handling.
- Group related properties/methods with // MARK: - Section.
- Keep line length reasonable (~120 chars).

## Common Issues

**Build fails after file move**
- Xcode project references must be updated manually if not using git mv.
- Clean build folder: Cmd+Shift+K.

**Agent not connecting**
- Check agent binary path in Settings > Agents.
- Verify agent supports ACP protocol.
- Check console logs for subprocess stderr.

**Terminal not displaying**
- GhosttyTerminal requires proper frame size and Metal support.
- Check terminal theme configuration in Resources/.
- Verify process spawn permissions.

## Resources

- Agent Client Protocol Spec: https://agentclientprotocol.com
- Ghostty Terminal: https://github.com/ghostty-org/ghostty
- swift-markdown: https://github.com/apple/swift-markdown
- libgit2: https://libgit2.org/
