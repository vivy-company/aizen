# Aizen Project - Agent Instructions

## Project Overview

Aizen is a macOS developer tool for managing Git worktrees with integrated terminal, file browser, web browser, and AI agent support via the Agent Client Protocol (ACP).

## Architecture

### Current Direction

Aizen is migrating incrementally from top-level technical buckets toward a feature-first architecture.

Target direction:

```text
aizen/
├── App/
├── Features/
│   ├── Chat/
│   ├── Worktree/
│   ├── Repository/
│   ├── Browser/
│   ├── Files/
│   ├── Terminal/
│   ├── Workspace/
│   ├── Settings/
│   └── Search/
├── Platform/
├── Integrations/
├── Persistence/
├── Shared/
├── Assets.xcassets/
├── Resources/
└── cli/
```

Each migrated feature should use:

```text
FeatureName/
├── Domain/
├── Application/
├── Infrastructure/
├── UI/
└── Testing/
```

This is an incremental migration, not a single rewrite. Legacy folders still exist during transition, but new substantial work should prefer the target feature structure instead of deepening the old buckets.

See:
- `docs/specs/feature-first-architecture-migration-spec.md`

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

### Architecture Policy

- Treat Aizen as greenfield for internal architecture work, not as a legacy codebase that must preserve internal structure.
- Apply this policy to refactors, bug fixes, and new feature work.
- Prefer root-cause changes over local patches that merely fit the current shape.
- When adding something new, prefer the design that makes the system more scalable, maintainable, and coherent, even if that means reworking surrounding code.
- Do not preserve internal backward compatibility just to avoid touching call sites.
- Do not add shims, adapter layers, parallel code paths, or temporary wrappers unless there is a real external compatibility requirement.
- When a design is wrong, replace it from the ground up so the resulting code is simpler and more maintainable.
- Keep compatibility only at genuine external boundaries:
  - persisted Core Data / on-disk data
  - user-visible behavior that must intentionally remain stable
  - external protocols, CLIs, APIs, and integrations
- Remove dead code when changing systems instead of leaving legacy paths in place.
- If improving a feature or fixing a bug requires breaking internal structure to make the system better, prefer the cleaner break.

### Feature-First Migration Policy

- New substantial feature work should land in `Features/<FeatureName>/` whenever the ownership boundary is clear.
- For migrated features, keep all new code inside that feature subtree.
- Do not add new broad top-level `Manager` types unless they are truly app-global.
- Do not place non-view feature orchestration in `Views/`.
- Do not place feature-specific orchestration in `Utilities/`.
- Prefer explicit ownership names such as `Store`, `Coordinator`, `Repository`, `Registry`, or `Service` based on actual responsibility.
- `Domain` is for pure feature types and policies.
- `Application` is for feature state and orchestration.
- `Infrastructure` is for Core Data, ACP, libgit2, WebKit, filesystem, and other external integrations.
- `UI` is for SwiftUI/AppKit presentation only.

### When Working on Features

1. Respect feature boundaries first:
   - migrated feature code -> `Features/<FeatureName>/`
   - app entry/composition/window wiring -> `App/`
   - platform wrappers such as Ghostty/libgit2/Xcode -> `Platform/` or feature `Infrastructure/`
   - cross-feature external integrations -> `Integrations/`
   - persistence implementation -> `Persistence/` or feature `Infrastructure/`

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

- If a feature subtree exists, place new feature code there instead of legacy buckets.
- If a feature is large and scattered, prefer creating `Features/<FeatureName>/` rather than adding more files under `Services/`, `Views/`, or `Managers/`.
- Keep reusable cross-feature UI in `Shared/` once that subtree exists; otherwise use the existing shared-components area until migrated.
- Keep utilities generic. If logic is feature-specific, it does not belong in `Utilities/`.
- Use `git mv` for moves when practical to preserve history.

### Commit Policy

- Prefer atomic commits.
- Each commit should represent one coherent change with a clear purpose.
- Do not mix structural refactors, behavior changes, and incidental cleanup in the same commit unless they are inseparable.
- For feature-first migrations, prefer a sequence such as:
  1. compile-stable file moves
  2. ownership split / dependency updates
  3. behavior-preserving cleanup
  4. tests
- Before creating a commit, review the diff and exclude unrelated changes.

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
- VVDevKit highlighting: Tree-sitter syntax highlighting.
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
