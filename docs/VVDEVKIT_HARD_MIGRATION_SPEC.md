# VVDevKit Hard Migration Spec

Status: Locked (execution in progress)
Date: 2026-02-23
Last Updated: 2026-02-23
Owners: Aizen core

## 1. Decision

We will do a hard cutover to VVDevKit with no backward-compatibility layer and no runtime feature flags.

This means:
- Legacy editor/old markdown/old timeline/old diff code will be removed.
- Aizen will depend directly on VVDevKit surfaces.
- Any gaps needed for Aizen behavior will be patched in VVDevKit first, in a generic way.

## 2. Scope

In scope:
- Code editor migration to `VVCodeView`.
- Syntax highlighting migration to VVDevKit highlighting pipeline.
- Markdown migration to `VVMarkdownView`.
- Chat timeline migration to `VVChatTimeline` with generic custom entries.
- Diff migration to `VVDiffView` and `VVMultiBufferDiffView`.
- Removal of legacy implementations and legacy editor-package dependencies.

Out of scope:
- Incremental compatibility switches.
- Preserving legacy rendering internals.

## 3. VVDevKit Patch Contract

## 3.1 Generic Markdown Link Routing

Status: Done

Implemented API:
```swift
public enum VVMarkdownLinkDecision: Sendable {
    case handled
    case openExternally
    case ignore
}

public struct VVMarkdownLinkContext: Sendable {
    public let raw: String
    public let resolvedURL: URL?
    public let baseURL: URL?
}

public typealias VVMarkdownLinkHandler = @MainActor (VVMarkdownLinkContext) -> VVMarkdownLinkDecision
```

`VVMarkdownView` additions:
- `baseURL: URL?`
- `linkHandler: VVMarkdownLinkHandler?`

Behavior contract:
1. Resolve raw link against `baseURL` if applicable.
2. If `linkHandler` exists, call it first.
3. Follow decision:
- `.handled`: do nothing else.
- `.openExternally`: existing open behavior.
- `.ignore`: no-op.

Constraint:
- This remains app-agnostic; no Aizen-specific scheme in VVDevKit core.

## 3.2 Generic Chat Timeline Entries

Status: Done

Implemented model:
```swift
public enum VVChatTimelineEntry: Identifiable, Hashable, Sendable {
    case message(VVChatMessage)
    case custom(VVCustomTimelineEntry)
}

public struct VVCustomTimelineEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: String
    public let payload: Data
    public let revision: Int
    public let timestamp: Date?
}
```

Constraint:
- VVDevKit must not encode Aizen-specific tool-call semantics.
- `kind` + payload decoding belongs to host app.

## 3.3 Timeline State Callback

Status: Done

Implemented addition:
- `VVChatTimelineView.onStateChange: ((VVChatTimelineState) -> Void)?`
- SwiftUI bridge plumbing in `VVChatTimelineViewSwiftUI` and representable.

## 4. Aizen Hard Migration Plan

## 4.1 Dependencies

In `aizen.xcodeproj/project.pbxproj`:
- Add VVDevKit package.
- Link at minimum: `VVCode`, `VVMarkdown`, `VVChatTimeline`, `VVGit` (or umbrella `VVDevKit` if enough).
- Remove:
  - `Packages/*` legacy local editor forks
  - orphaned legacy symbol product dependencies if no longer required

Status: In progress
- Active code usage scan is clean for legacy editor-package dependencies and removed highlighting/diff coordinator symbols.

## 4.2 Code Editor + Highlighting

Replace:
- `aizen/Views/Components/CodeEditorView.swift` -> `VVCodeView`.

Remove:
- `aizen/Views/Components/GitDiffCoordinator.swift`
- `aizen/Services/Highlighting/TreeSitterHighlighter.swift`
- `aizen/Services/Highlighting/HighlightingQueue.swift`

New/updated support:
- `Ghostty -> VVTheme` mapper.
- language mapping to `VVLanguage`.
- git gutter fed via unified diff string parsed by VV stack.

Status: Done

## 4.3 Markdown

Replace rendering entry points:
- `aizen/Views/Chat/Components/MarkdownContentView.swift`
- markdown preview use in `aizen/Views/Files/Components/FileContentView.swift`

Remove legacy markdown stack:
- `aizen/Views/Chat/Components/Markdown/MarkdownView.swift`
- `aizen/Views/Chat/Components/Markdown/MarkdownTypes.swift`
- `aizen/Views/Chat/Components/Markdown/MarkdownListView.swift`
- `aizen/Views/Chat/Components/Markdown/MermaidDiagramView.swift`
- `aizen/Views/Chat/Components/Markdown/MarkdownImageView.swift`

Status: In progress
- VV markdown is now the renderer.
- Local file links route through VVDevKit link handler into Aizen editor routing.
- Remaining cleanup is structural/file-level legacy deletion only.

## 4.4 Diffs

Replace:
- `aizen/Views/Worktree/Components/Git/DiffView.swift` -> `VVDiffView` / `VVMultiBufferDiffView`
- `aizen/Views/Chat/Components/InlineDiffView.swift` -> `VVDiffView`

Remove:
- `aizen/Views/Chat/Components/SelectableDiffView.swift`
- `aizen/Utilities/DiffParser.swift`
- `aizen/Views/Worktree/Components/Git/DiffLineParser.swift`

Notes:
- Use `VVMultiBufferDiffView.onHunkAction` for comment hooks.

Status: Done (current implementation uses `VVDiffView` surfaces).

## 4.5 Chat Timeline

Replace:
- `aizen/Views/Chat/Components/ChatMessageList.swift`
- `aizen/Views/Chat/ChatSessionViewModel+Timeline.swift` timeline assembly logic
- `aizen/Models/TimelineItem.swift`

With:
- `VVChatTimelineController` + mixed `VVChatTimelineEntry` mapping.

Custom entry kinds in Aizen:
- `toolCallGroup`
- `turnSummary`
- `planRequest`

Status: In progress
- `ChatMessageList` renders via `VVChatTimelineViewSwiftUI`.
- Non-message rows map to `VVCustomTimelineEntry`.
- Legacy timeline row views and unused child-tool-call plumbing have been removed.
- Remaining cleanup: collapse legacy `TimelineItem`/grouping model to direct VV timeline entry assembly.

## 4.6 Legacy Deletion Pass

Delete all remaining legacy editor-package imports and code paths.

Target removal check:
- `rg "SourceEditor|EditorTheme|CodeLanguage" aizen`
returns no legacy runtime dependencies (except temporary migration comments, then remove those too).

Status: In progress

## 5. Remaining Execution Order

1. Collapse `TimelineItem`-based assembly to direct VV timeline entry assembly.
2. Finish markdown/diff file-level deletion cleanup.
3. Ensure project/package references are clean (no orphaned legacy refs).
4. Run compile verification and quick functional checks.
5. Update this spec to `Completed`.

## 6. Acceptance Criteria

- Project builds with no legacy local editor-package dependencies.
- Chat markdown local-file links open editor paths through VVMarkdown link handler.
- Timeline supports message + custom rows without Aizen-specific code in VVDevKit.
- Worktree and inline diffs render through VVDevKit surfaces.
- Old markdown/timeline/diff/editor implementations are removed from repo.

## 7. Verification Checklist

- `rg "SourceEditor|CodeLanguage" aizen aizen.xcodeproj/project.pbxproj` has no active dependency usage.
- `xcodebuild -project aizen.xcodeproj -scheme aizen -configuration Debug build` succeeds.
- `xcodebuild -project aizen.xcodeproj -scheme "aizen nightly" -configuration Debug build` succeeds.
- Chat:
  - streaming assistant message render
  - local link open in editor
  - custom timeline rows render and update
- Diffs:
  - single-file
  - multi-file
  - chat inline diff

## 8. Progress Snapshot (2026-02-23)

- Done:
  - VVDevKit markdown link routing patch.
  - VVDevKit timeline custom entry model.
  - VVDevKit timeline state-change callback patch.
  - Aizen code editor migration to `VVCodeView`.
  - Aizen diff rendering migration to `VVDiffView`.
  - Aizen chat list switched to VV timeline renderer.
  - Legacy chat timeline row views removed (`ToolCallView`, `ToolCallGroupView`, `TurnSummaryView`, `ToolDetailsSheet`).
  - Unused timeline plumbing removed (`childToolCalls*`, `turnAnchorMessageId`, dead container inputs).
- In progress:
  - Timeline model cleanup (`TimelineItem` to direct VV entries).
  - Final markdown/timeline file deletion pass.
  - Final project reference cleanup.
