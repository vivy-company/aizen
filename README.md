# Aizen

Manage multiple Git branches simultaneously with dedicated terminals and agents in parallel.

![Aizen Demo](https://r2.aizen.win/demo.png)

## Features

- **Workspace Management**: Organize repositories into workspaces with color coding and search
- **Git Worktree Support**: Create, manage, and switch Git worktrees with visual UI and status indicators
- **Integrated Terminal**: GPU-accelerated terminal emulator using libghostty with split panes, multiple tabs, and theme support
- **AI Agent Integration**: Support for Claude, Codex, Gemini, Kimi, and custom agents via Agent Client Protocol (ACP) with multi-session chat and plan approval
- **Voice Input**: Real-time voice recording with waveform visualization and on-device speech-to-text transcription
- **Git Operations**: Comprehensive sidebar for staging, committing, pushing, pulling, branching, and diff visualization
- **Integrated File Browser**: Hierarchical file tree navigation with content preview, editing, and syntax highlighting
- **Built-in Web Browser**: Multi-tab browser with navigation controls, integrated per worktree for documentation and references
- **Onboarding Experience**: Guided setup wizard for first-time users covering agents, permissions, and preferences
- **Comprehensive Settings**: Detailed configuration panels for general, appearance, terminal, agents, editor, updates, and advanced options
- **Agent Management**: Automatic discovery, installation (NPM, GitHub), updates, and authentication handling
- **Automatic Updates**: Sparkle-based update system with configurable check intervals
- **Advanced Markdown Rendering**: Full markdown support with syntax highlighting, diagrams (Mermaid), and image handling
- **Tree-sitter Syntax Highlighting**: High-performance highlighting for 50+ languages using CodeEdit's Tree-sitter integration
- **Custom Agents**: Add and configure custom ACP-compatible agents with executable paths and launch arguments

## Requirements

- macOS 13.5+
- Xcode 16.0+ (for building from source)
- Swift 5.0+ (for building from source)

## Dependencies

- [libghostty](https://github.com/ghostty-org/ghostty) - GPU-accelerated terminal emulator
- Apple's Markdown (built-in framework) - Markdown parsing and rendering
- [CodeEdit](https://github.com/CodeEditApp/CodeEdit) packages (SourceEditor, TextView, Symbols, Languages) - Code editing, syntax highlighting with Tree-sitter support for 50+ languages
- [Sparkle](https://github.com/sparkle-project/Sparkle) (2.0+) - Automatic updates
- WebKit (built-in framework) - Integrated web browsing capabilities

## Installation

Download the latest release from [aizen.win](https://aizen.win).

The app is signed and notarized with an Apple Developer certificate.

### Build from Source

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
- **Claude**: Installed via NPM (`@zed-industries/claude-code-acp`)
- **Codex**: Installed via GitHub releases (`openai/openai-agent`)
- **Gemini**: Installed via NPM (`@google/gemini-cli` with `--experimental-acp`)
- **Kimi**: Installed via GitHub releases (`MoonshotAI/kimi-cli`)
- **Custom Agents**: Add custom ACP-compatible agents

The app can automatically discover and install agents, or you can manually configure paths.

### Editor

Configure default code editor in Settings > General:
- VS Code (`code`)
- Cursor (`cursor`)
- Sublime Text (`subl`)

### Updates

Automatic update checks via Sparkle. Configure in Settings > Updates.

## Usage

### Basic Workflow

1. **Onboarding**: Complete guided setup for agents, permissions, and preferences
2. **Create a workspace**: Organize projects with color coding and search
3. **Add Git repositories**: Link repositories to workspaces with validation
4. **Create worktrees**: Manage multiple branches with dedicated sessions (Terminal, Browser, Files, Chat)
5. **Navigate files**: Use integrated file browser for tree navigation and editing
6. **Browse documentation**: Open multi-tab browser for references and docs
7. **Open terminals**: GPU-accelerated terminals with splits and themes
8. **Use AI agents**: Chat with agents for code assistance, with voice input and plan approval
9. **Git operations**: Stage, commit, diff, push/pull via dedicated sidebar
10. **Configure settings**: Customize appearance, editor, terminal, and agents

### Terminal

- Split panes horizontally or vertically
- GPU-accelerated rendering via libghostty
- Multiple terminal tabs per worktree
- Configurable themes and fonts

### Chat & Agents

- Multiple chat modes (cycle with `⇧ ⇥`)
- Support for text and voice input
- Plan approval for complex operations
- Markdown rendering with syntax highlighting

## Keyboard Shortcuts

- `⌘ D` - Split terminal right
- `⌘ ⇧ D` - Split terminal down
- `⌘ W` - Close terminal pane
- `⌘ T` - New terminal tab
- `⇧ ⇥` - Cycle chat mode
- `ESC` - Interrupt running agent
- `⌘ O` - Open file in browser
- `⌘ N` - New browser tab
- `⌘ +` / `⌘ -` - Zoom in/out in editor/browser

## Development

### Project Structure

The codebase is organized by domain for better maintainability and scalability:

```
aizen/
├── App/
│   └── aizenApp.swift                    # App entry point and window management
│
├── Models/
│   ├── ACP/
│   │   └── ACPTypes.swift                # Agent Client Protocol type definitions
│   └── Agent/                            # Agent domain models
│
├── Services/
│   ├── Agent/                            # AI agent lifecycle and ACP integration
│   │   ├── ACP/                          # ACP protocol implementation
│   │   │   ├── ACPClient.swift           # ACP JSON-RPC client and subprocess management
│   │   │   └── Internal/                 # ACP utilities (process manager, request router, error handling)
│   │   ├── Delegates/                    # Session delegates for notifications and auth
│   │   ├── Installers/                   # Agent installers (NPM, GitHub releases)
│   │   ├── AgentSession.swift            # Multi-session agent state (with auth, notifications, messaging)
│   │   ├── AgentRegistry.swift           # Agent metadata storage and discovery
│   │   ├── AgentRouter.swift             # Incoming request routing
│   │   ├── AgentDiscoveryService.swift   # System-wide agent detection
│   │   ├── AgentInstaller.swift          # Unified installer orchestration
│   │   ├── AgentUpdater.swift            # Automatic agent updates
│   │   └── AgentVersionChecker.swift     # Version compatibility checks
│   ├── Git/                              # Git integration and operations
│   │   ├── Core/                         # Core Git command execution (GitCommandExecutor)
│   │   ├── Domain/                       # Specialized Git services
│   │   │   ├── GitBranchService.swift    # Branch management
│   │   │   ├── GitDiffService.swift      # Diff computation and parsing
│   │   │   ├── GitStagingService.swift   # Staging/unstaging files
│   │   │   ├── GitStatusService.swift    # Repository status monitoring
│   │   │   └── GitWorktreeService.swift  # Worktree creation and management
│   │   ├── Repository/                   # Repository filesystem operations
│   │   │   └── RepositoryFileSystemManager.swift # Path resolution and validation
│   │   ├── GitRepositoryService.swift    # High-level repository operations
│   │   ├── RepositoryManager.swift       # Repository lifecycle and persistence
│   │   ├── GitDiffProvider.swift         # Diff data provider for UI
│   │   ├── GitOperationHandler.swift     # UI-driven Git commands
│   │   └── FileService.swift             # General file operations
│   ├── Audio/                            # Voice input and transcription
│   │   ├── AudioService.swift            # Unified audio recording and transcription
│   │   ├── AudioRecordingService.swift   # AVFoundation recording with waveform
│   │   ├── SpeechRecognitionService.swift # On-device speech-to-text
│   │   └── AudioPermissionManager.swift  # Microphone permission handling
│   ├── FileIcon/                         # File type icon resolution
│   │   ├── FileIconService.swift         # Icon lookup and caching
│   │   └── FileIconMapper.swift          # Extension-to-icon mapping
│   ├── Highlighting/                     # Syntax highlighting engine
│   │   └── TreeSitterHighlighter.swift   # Tree-sitter based highlighting service
│   ├── Input/
│   │   └── KeyboardShortcutManager.swift # Global shortcut registration
│   ├── Persistence/
│   │   └── Persistence.swift             # Core Data setup and migration
│   └── AppDetector.swift                 # External app detection (VS Code, Cursor, etc.)
│
├── Views/
│   ├── ContentView.swift                 # Main three-column navigation layout
│   ├── Onboarding/                       # Guided first-time setup wizard
│   │   └── OnboardingView.swift          # Onboarding screens and flows
│   ├── Settings/                         # Comprehensive settings panels
│   │   ├── SettingsView.swift            # Settings navigation container
│   │   ├── GeneralSettingsView.swift     # General app preferences
│   │   ├── AppearanceSettingsView.swift  # Theme and UI customization
│   │   ├── EditorSettingsView.swift      # Code editor configuration
│   │   ├── TerminalSettingsView.swift    # Terminal appearance and behavior
│   │   ├── AgentsSettingsView.swift      # AI agent management
│   │   ├── UpdateSettingsView.swift      # Update preferences
│   │   └── AdvancedSettingsView.swift    # Advanced options and reset
│   ├── Workspace/
│   │   ├── WorkspaceSidebarView.swift    # Workspace sidebar with search and creation
│   │   ├── WorkspaceCreateSheet.swift    # New workspace dialog
│   │   └── WorkspaceEditSheet.swift      # Workspace editing dialog
│   ├── Worktree/
│   │   ├── WorktreeListView.swift        # Worktree listing with search
│   │   ├── WorktreeDetailView.swift      # Worktree details with tabs (Git, Files, Browser, Chat)
│   │   ├── WorktreeViewModel.swift       # Worktree state management
│   │   ├── WorktreeCreateSheet.swift     # New worktree dialog
│   │   ├── RepositoryAddSheet.swift      # Add repository dialog
│   │   ├── FileTabView.swift             # File tabs within worktree
│   │   └── Components/
│   │       ├── GitSidebarView.swift      # Git operations sidebar (stage, commit, diff)
│   │       ├── WorktreeListItemView.swift # Individual worktree row
│   │       └── WorktreeSessionTabs.swift # Session tab management (Terminal, Browser, etc.)
│   ├── Files/
│   │   ├── FileBrowserSessionView.swift  # Main file browser interface
│   │   ├── FileBrowserViewModel.swift    # File browser state and navigation
│   │   └── Components/
│   │       ├── FileTreeView.swift        # Hierarchical file tree
│   │       └── FileContentTabView.swift  # File content viewer with tabs
│   ├── Browser/
│   │   ├── BrowserTabView.swift          # Multi-tab web browser
│   │   ├── BrowserSessionManager.swift   # Browser session management
│   │   └── Components/
│   │       └── BrowserControlBar.swift   # Browser navigation controls
│   ├── Chat/
│   │   ├── ChatTabView.swift             # Chat session tabs
│   │   ├── ChatSessionView.swift         # Individual chat interface
│   │   ├── ChatSessionViewModel.swift    # Chat logic and state (with sub-modules for messages, attachments, timeline)
│   │   ├── ToolCallView.swift            # Tool execution visualization
│   │   ├── AgentIconView.swift           # Agent avatars and icons
│   │   ├── ACPContentViews.swift         # ACP message rendering
│   │   ├── VoiceRecordingView.swift      # Voice input with live waveform
│   │   ├── PlanApprovalDialog.swift      # Agent plan review and approval
│   │   ├── AgentPlanDialog.swift         # Agent plan execution progress
│   │   └── Components/
│   │       ├── ChatInputBar.swift        # Message input with attachments and voice
│   │       ├── MarkdownContentView.swift # Advanced markdown rendering (with Mermaid support)
│   │       ├── CodeBlockView.swift       # Syntax-highlighted code blocks
│   │       └── ContentBlockView.swift    # Multi-format content blocks
│   ├── Terminal/
│   │   ├── TerminalTabView.swift         # Terminal session tabs
│   │   ├── TerminalSplitLayout.swift     # Split pane layout for terminals
│   │   └── Components/
│   │       ├── TerminalViewWrapper.swift # Ghostty terminal wrapper
│   │       └── TerminalPaneView.swift    # Individual terminal pane
│   └── Components/                       # Reusable UI components
│       ├── CodeEditorView.swift          # Syntax-highlighted code editor
│       ├── FileIconView.swift            # File type icons
│       └── GitDiffCoordinator.swift      # Git diff rendering
│
├── GhosttyTerminal/                      # libghostty integration
│   └── Ghostty.*.swift                   # Terminal implementation
│
├── Managers/
│   ├── ChatSessionManager.swift          # Chat session lifecycle
│   └── ToastManager.swift                # Toast notification system
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

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this software except in compliance with the License. You may obtain a copy of the License at:

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

Copyright © 2025 Vivy Technologies Co., Limited
