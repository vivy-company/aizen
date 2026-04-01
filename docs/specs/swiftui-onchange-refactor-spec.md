# SwiftUI `.onChange` Refactor Spec

## Scope

- Audit target: `aizen` Swift files using SwiftUI `.onChange(`
- Inventory at initial validation pass: 103 call sites across 42 Swift files
- Inventory after full implementation pass: 0 call sites across 0 Swift files
- Goal: reduce fragile imperative state propagation, especially:
  - event delivery disguised as observed state
  - async work kicked off from `.onChange`
  - duplicated or overlapping observers
  - prop-to-local-state mirroring spread across many small observers

This spec is intentionally not a blanket ban on `.onChange`. Some sites are correct and should stay. The refactor target is the subset where `.onChange` is being used as a coordinator, event bus, or async trigger.

## Implementation Status

The refactor is now fully implemented in the app target. Literal SwiftUI `.onChange(` usage has been removed from `aizen` Swift files. The earlier high-value coordinator, async-trigger, event-flag, geometry, scroll, focus, and selection-sync sites are all converted to `.task(id:)`, explicit bindings/actions, or derived state as appropriate.

Completed in code:

- `ContentView`
- `RootView`
- `SessionsListView`
- `FileSearchView`
- `MCPMarketplaceView`
- `ChatMessageList` style-observer consolidation
- `ChatInputBar`
- `WorktreeListItemView`
- `TerminalPaneView` voice-action path
- `ANSIParser`
- `TranscriptionSettingsView`
- `GeneralSettingsView`
- `PostCreateActionsView`
- `CustomAgentFormView`
- `WorktreeCreateSheet`
- `BranchSelectorView`
- `VVCodeSnippetView`
- `CodeEditorView`
- `GitPanelWindowController` branch-selection path
- `WorkflowRunDetailView`
- `CommandPaletteWindowController`
- `ChatSessionView`
- `FileBrowserSessionView`
- `AgentDetailView`
- `PullRequestDetailPane`
- `GitPanelWindowContent`
- `ChatTabView`
- `WorktreeDetailView`
- `FileContentView`
- `FileSearchWindowController`
- `InlineAutocompleteView`
- `PlanApprovalDialog`
- `CompanionDivider`
- `CompanionGitDiffView`
- `DiffView`
- `ActiveWorktreesView`
- `XcodeLogSheetView`
- `VoiceRecordingView`
- `SplitTerminalView`

## Decision Rules

- Keep `.onChange` when it performs a small imperative UI side effect that is tightly coupled to view state.
- Prefer `.task(id:)` when the effect is async, debounced, cancellable, or should run on first appearance and again when an input changes.
- Prefer explicit action closures or custom `Binding` setters when the change originates from direct user interaction in a control.
- Prefer derived/computed state when the value can be recomputed from inputs without mutating local state.
- Prefer coordinator objects or explicit callback APIs when the observed value is really an event channel rather than durable state.
- Merge neighboring `.onChange` blocks when they all trigger the same downstream work.

## Priority Summary

Priority here means implementation order, not importance. Low-priority items are still valid refactor targets; they are just less urgent or depend on earlier cleanup.

### P0: implement first

- Completed in current pass:
  - `aizen/Views/ContentView.swift`
  - `aizen/Views/RootView.swift`
  - `aizen/Views/Chat/SessionsListView.swift`
  - `aizen/Views/Search/FileSearchView.swift`
  - `aizen/Views/Settings/Components/MCP/MCPMarketplaceView.swift`
  - `aizen/Views/Chat/Components/ChatMessageList.swift`
  - `aizen/Views/Chat/Components/ChatInputBar.swift`
  - `aizen/Views/Worktree/Components/WorktreeListItemView.swift`
  - `aizen/Views/Terminal/Components/TerminalPaneView.swift` for `voiceAction`
  - `aizen/Utilities/ANSIParser.swift`

### P1: implement next

- Completed in current pass:
  - `aizen/Views/Settings/TranscriptionSettingsView.swift`
  - `aizen/Views/Settings/GeneralSettingsView.swift`
  - `aizen/Views/Settings/Components/PostCreateActionsView.swift`
  - `aizen/Views/Settings/Components/CustomAgentFormView.swift`
  - `aizen/Views/Worktree/WorktreeCreateSheet.swift`
  - `aizen/Views/Worktree/Components/BranchSelectorView.swift`
  - `aizen/Views/Components/VVCodeSnippetView.swift`
  - `aizen/Views/Components/CodeEditorView.swift`
  - `aizen/Views/Worktree/Components/Git/GitPanelWindowController.swift`
  - `aizen/Views/Worktree/Components/Git/Workflow/WorkflowRunDetailView.swift`
  - `aizen/Views/Chat/ChatSessionView.swift`
  - `aizen/Views/Chat/Components/CompanionDivider.swift`

### P2: implement later / optional cleanup

- Completed in current pass:
  - scroll syncing conversions
  - selection highlighting conversions
  - geometry reaction conversions
  - lightweight runtime visibility conversions
- This tier is complete for the app target.

## File-by-File Spec

### `aizen/Views/ContentView.swift`

- [ContentView.swift](/Users/uyakauleu/development/aizen/aizen/Views/ContentView.swift#L209): `selectedWorkspace`
  - Replace with: explicit selection actions and custom bindings, for example `selectWorkspace(_:)`
  - Why: this observer mutates several other pieces of state (`selectedRepository`, `selectedWorktree`, `isCrossProjectSelected`) and acts like a coordinator. This is the largest state-cascade in the repo and is the main place where `.onChange` is doing view-controller work.
- [ContentView.swift](/Users/uyakauleu/development/aizen/aizen/Views/ContentView.swift#L237): `selectedRepository`
  - Replace with: explicit `selectRepository(_:)` action, plus a dedicated async persistence helper for saving the last repo
  - Why: same coordinator smell. It branches between cross-project routing, repo deletion fallback, persisted selection restore, and async save scheduling.
- [ContentView.swift](/Users/uyakauleu/development/aizen/aizen/Views/ContentView.swift#L275): `selectedWorktree`
  - Replace with: explicit `selectWorktree(_:)` action called by the UI and by restore flows
  - Why: this is durable navigation state and should be updated through a single selection pathway, not by an observer that also rewrites selection again when the worktree is deleted.
- [ContentView.swift](/Users/uyakauleu/development/aizen/aizen/Views/ContentView.swift#L296): `crossProjectWorktree?.id?.uuidString`
  - Replace with: fold into `selectCrossProjectWorktree(_:)` or the same explicit cross-project selection path
  - Why: this is bookkeeping attached to a selection change, not an independent observer.
- [ContentView.swift](/Users/uyakauleu/development/aizen/aizen/Views/ContentView.swift#L302): `isCrossProjectSelected`
  - Replace with: explicit `setCrossProjectSelected(_:)`
  - Why: toggling this flag currently mutates zen mode, clears selection, prepares workspace state, and presents onboarding. That should be one explicit intentful action.
- [ContentView.swift](/Users/uyakauleu/development/aizen/aizen/Views/ContentView.swift#L320): `zenModeEnabled`
  - Keep, but move rule into the same cross-project coordinator if possible
  - Why: the invariant is valid, but it belongs with the cross-project mode transition logic rather than as a separate guard observer.

### `aizen/Views/RootView.swift`

- [RootView.swift](/Users/uyakauleu/development/aizen/aizen/Views/RootView.swift#L50): `gitChangesContext`
  - Replace with: explicit coordinator/action API, not state observation
  - Why: `gitChangesContext` is functioning as a command bus to open and close a detached window. This is a poor fit for `.onChange` because the value is not stable app state; it is effectively an event. Introduce a `GitPanelCoordinator` or `presentGitPanel(for:)` callback from `WorktreeDetailView`.

### `aizen/Views/CommandPalette/CommandPaletteWindowController.swift`

- [CommandPaletteWindowController.swift](/Users/uyakauleu/development/aizen/aizen/Views/CommandPalette/CommandPaletteWindowController.swift#L294): `allWorktrees.count`
  - Replace with: consolidate into one snapshot refresh path, ideally `.task(id: snapshotKey)` or rely on the existing Core Data change publisher
  - Why: this overlaps with the existing `.onReceive(.NSManagedObjectContextObjectsDidChange)` block and only keys off `count`, which can miss same-count content changes.
- [CommandPaletteWindowController.swift](/Users/uyakauleu/development/aizen/aizen/Views/CommandPalette/CommandPaletteWindowController.swift#L297): `allWorkspaces.count`
  - Replace with: same consolidation as above
  - Why: duplicate refresh pathway.
- [CommandPaletteWindowController.swift](/Users/uyakauleu/development/aizen/aizen/Views/CommandPalette/CommandPaletteWindowController.swift#L300): `currentWorktreeId`
  - Replace with: `.task(id: currentWorktreeId)` or merged refresh helper
  - Why: this is a valid refresh trigger, but it should be part of the same snapshot refresh mechanism rather than a separate observer.
- [CommandPaletteWindowController.swift](/Users/uyakauleu/development/aizen/aizen/Views/CommandPalette/CommandPaletteWindowController.swift#L445): `viewModel.selectedIndex`
  - Keep
  - Why: `ScrollViewReader` scrolling on selection change is an appropriate imperative UI side effect.

### `aizen/Views/Search/FileSearchWindowController.swift`

- [FileSearchWindowController.swift](/Users/uyakauleu/development/aizen/aizen/Views/Search/FileSearchWindowController.swift#L355): `viewModel.selectedIndex`
  - Keep
  - Why: scroll-following a highlighted selection is a good `.onChange` use.

### `aizen/Views/Search/FileSearchView.swift`

- [FileSearchView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Search/FileSearchView.swift#L77): `viewModel.searchQuery`
  - Replace with: remove entirely
  - Why: `FileSearchViewModel` already debounces and calls `performSearch()` from a Combine pipeline in `setupSearchDebounce()`. The view-level `.onChange` duplicates the search trigger and can cause redundant work.
- [FileSearchView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Search/FileSearchView.swift#L134): `viewModel.selectedIndex`
  - Keep
  - Why: scroll alignment side effect.

### `aizen/Views/Settings/TranscriptionSettingsView.swift`

- [TranscriptionSettingsView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/TranscriptionSettingsView.swift#L175): `providerRaw`
  - Replace with: custom picker `Binding` setter, or a single `.task(id: providerRaw)` if refresh becomes async
  - Why: this comes directly from picker interaction and is better modeled where the selection is written.
- [TranscriptionSettingsView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/TranscriptionSettingsView.swift#L182): `whisperModelId`
  - Replace with: custom `Binding` setter on the model picker
  - Why: same direct user-edit path.
- [TranscriptionSettingsView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/TranscriptionSettingsView.swift#L186): `parakeetModelId`
  - Replace with: custom `Binding` setter on the model picker
  - Why: same as above.

### `aizen/Views/Settings/GeneralSettingsView.swift`

- [GeneralSettingsView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/GeneralSettingsView.swift#L251): `selectedLanguage`
  - Replace with: custom `Binding` setter on the picker
  - Why: this is a direct control write. The `hasLoadedLanguage` guard can live in the setter or be avoided by initializing `selectedLanguage` from persisted state before rendering the picker.

### `aizen/Views/Settings/Components/PostCreateActionsView.swift`

- [PostCreateActionsView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/Components/PostCreateActionsView.swift#L49): `addActionRequested`
  - Replace with: explicit callback or tokenized request value, not a boolean watched by the child
  - Why: this is an event, not durable state. Boolean event flags are a recurrent smell in the repo.

### `aizen/Views/Settings/Components/CustomAgentFormView.swift`

- [CustomAgentFormView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/Components/CustomAgentFormView.swift#L101): `executablePath`
  - Replace with: custom text-field binding setter that clears `pathValidationResult`
  - Why: direct user input should clear validation inline at the point of write.
- [CustomAgentFormView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/Components/CustomAgentFormView.swift#L119): `launchArgsText`
  - Replace with: same custom binding setter approach
  - Why: same pattern.
- [CustomAgentFormView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/Components/CustomAgentFormView.swift#L224): `environmentVariables`
  - Replace with: clear validation in the mutation entry points for the environment variable editor
  - Why: validation reset should happen where the form mutates, not from a top-level watcher.

### `aizen/Views/Settings/Components/AgentDetailView.swift`

- [AgentDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/Components/AgentDetailView.swift#L651): `metadata.id`
  - Replace with: `.task(id: metadata.id)`
  - Why: loading draft environment state is lifecycle/data-load work and `.task(id:)` communicates that intent better while covering initial load and identity changes in one place.

### `aizen/Views/Settings/Components/SFSymbolPickerView.swift`

- [SFSymbolPickerView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/Components/SFSymbolPickerView.swift#L194): `searchText`
  - Replace with: custom search-field binding setter or a single merged `.task(id: paginationResetKey)`
  - Why: resetting `displayLimit` is deterministic from the filter inputs and should happen at the input write site.
- [SFSymbolPickerView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/Components/SFSymbolPickerView.swift#L197): `selectedCategory`
  - Replace with: same as above
  - Why: both observers do the same work and should be merged.

### `aizen/Views/Settings/Components/MCP/MCPMarketplaceView.swift`

- [MCPMarketplaceView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/Components/MCP/MCPMarketplaceView.swift#L119): `searchQuery`
  - Replace with: `.task(id: searchQuery)` and move the debounce sleep into that task
  - Why: this is textbook cancellable async search work. `.task(id:)` is a better fit than `.onChange` + manually managed `Task`.

### `aizen/Views/Files/FileBrowserSessionView.swift`

- [FileBrowserSessionView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Files/FileBrowserSessionView.swift#L76): `fileToOpenFromSearch`
  - Replace with: explicit file-open action/coordinator, or `.task(id: fileToOpenFromSearch)` if the binding stays
  - Why: this is another event-channel binding. The child observes a transient command value and clears it after consumption.

### `aizen/Views/Files/Components/FileContentView.swift`

- [FileContentView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Files/Components/FileContentView.swift#L56): `geometry.size.width`
  - Keep
  - Why: local geometry measurement with a simple width cache is reasonable. If the deployment target later allows it cleanly, `onGeometryChange` or a preference-key helper would be cleaner.

### `aizen/Views/Components/VVCodeSnippetView.swift`

- [VVCodeSnippetView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Components/VVCodeSnippetView.swift#L89): `text`
  - Replace with: one consolidated `.task(id: documentSyncKey)` that synchronizes `VVDocument`
  - Why: this view is mirroring immutable props into mutable local editor state. A single sync task is clearer than several tiny observers.
- [VVCodeSnippetView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Components/VVCodeSnippetView.swift#L94): `languageHint`
  - Replace with: merge into `documentSyncKey`
  - Why: duplicate document sync path.
- [VVCodeSnippetView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Components/VVCodeSnippetView.swift#L97): `filePath`
  - Replace with: merge into `documentSyncKey`
  - Why: duplicate document sync path.
- [VVCodeSnippetView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Components/VVCodeSnippetView.swift#L100): `mimeType`
  - Replace with: merge into `documentSyncKey`
  - Why: duplicate document sync path.

### `aizen/Views/Components/CodeEditorView.swift`

- [CodeEditorView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Components/CodeEditorView.swift#L93): `content`
  - Replace with: consolidated `.task(id: editorSyncKey)`
  - Why: prop-to-document mirroring and diff scheduling should be centralized.
- [CodeEditorView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Components/CodeEditorView.swift#L101): `language`
  - Replace with: merge into the same sync task
  - Why: duplicate state mirror.
- [CodeEditorView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Components/CodeEditorView.swift#L107): `hasUnsavedChanges`
  - Replace with: `.task(id: hasUnsavedChanges)` or fold into the same diff-reload state machine
  - Why: this is async cancellation/restart logic and fits `.task(id:)` better than `.onChange`.

### `aizen/Views/Terminal/Components/SplitTerminalView.swift`

- [SplitTerminalView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Terminal/Components/SplitTerminalView.swift#L69): `isSelected`
  - Keep
  - Why: selection state bridging into the split controller is a small imperative sync.

### `aizen/Views/Terminal/Components/TerminalPaneView.swift`

- [TerminalPaneView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Terminal/Components/TerminalPaneView.swift#L109): `isFocused`
  - Keep
  - Why: AppKit/Ghostty focus bridging is a legitimate imperative side effect.
- [TerminalPaneView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Terminal/Components/TerminalPaneView.swift#L119): `focusRequestVersion`
  - Keep, but consider a tokenized focus request type later
  - Why: this is also an imperative bridge and not a data-flow bug.
- [TerminalPaneView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Terminal/Components/TerminalPaneView.swift#L130): `voiceAction`
  - Replace with: explicit action callback or tokenized command object
  - Why: this is an event bus, not state. The pane consumes the action and clears it. This matches the same smell as `addActionRequested` and `selectedBranchForSwitch`.
- [TerminalPaneView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Terminal/Components/TerminalPaneView.swift#L136): `showingVoiceRecording`
  - Keep
  - Why: parent callback notification for a local state toggle is acceptable.
- [TerminalPaneView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Terminal/Components/TerminalPaneView.swift#L700): `highlighted`
  - Keep
  - Why: local animation start/stop side effect.

### `aizen/Utilities/ANSIParser.swift`

- [ANSIParser.swift](/Users/uyakauleu/development/aizen/aizen/Utilities/ANSIParser.swift#L497): `logs`
  - Replace with: `.task(id: logs)`
  - Why: parsing is async-ish work and should use the lifecycle-aware task API instead of `.onAppear` + `.onChange`.

### `aizen/Views/Chat/VoiceRecordingView.swift`

- [VoiceRecordingView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/VoiceRecordingView.swift#L130): `timeline.date`
  - Keep
  - Why: reacting to `TimelineView` ticks is fine. This is not a state-management issue.

### `aizen/Views/Chat/ChatSessionView.swift`

- [ChatSessionView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/ChatSessionView.swift#L216): `geometry.size.width`
  - Keep
  - Why: local measurement sync.
- [ChatSessionView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/ChatSessionView.swift#L246): `isLayoutResizing`
  - Keep, but extract into a named helper
  - Why: this is specifically guarding against layout feedback during a resize pass.
- [ChatSessionView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/ChatSessionView.swift#L278): `isSelected`
  - Keep, but deduplicate logic with `.onAppear`
  - Why: selection lifecycle work is legitimate here. The problem is duplicated code, not the modifier choice.
- [ChatSessionView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/ChatSessionView.swift#L298): `inputText`
  - Replace with: `.task(id: inputText)` if `debouncedPersistDraft` remains asynchronous/debounced
  - Why: draft persistence is cancellable side-effect work and fits `.task(id:)` better.

### `aizen/Views/Chat/ChatTabView.swift`

- [ChatTabView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/ChatTabView.swift#L123): `selectedSessionId`
  - Keep, but merge with the session count sync helper
  - Why: this is selection bookkeeping for cache coordination.
- [ChatTabView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/ChatTabView.swift#L126): `sessions.count`
  - Replace with: a more stable identity key such as session IDs, or fold into the same sync routine run from the session source
  - Why: count-based observation is brittle when content changes without count changes.
- [ChatTabView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/ChatTabView.swift#L246): `geometry.size.width`
  - Keep
  - Why: layout clamp side effect.
- [ChatTabView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/ChatTabView.swift#L253): `leftPanelType`
  - Keep, but merge with the geometry clamp helper
  - Why: this is localized layout maintenance.
- [ChatTabView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/ChatTabView.swift#L258): `rightPanelType`
  - Keep, but merge with the geometry clamp helper
  - Why: same as above.

### `aizen/Views/Chat/SessionsListView.swift`

- [SessionsListView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/SessionsListView.swift#L71): `viewModel.selectedFilter`
  - Replace with: one `.task(id: reloadKey)`
  - Why: all five observers trigger the same async reload.
- [SessionsListView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/SessionsListView.swift#L74): `viewModel.searchText`
  - Replace with: same `reloadKey` task
  - Why: duplicate async trigger.
- [SessionsListView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/SessionsListView.swift#L77): `viewModel.selectedWorktreeId`
  - Replace with: same `reloadKey` task
  - Why: duplicate async trigger.
- [SessionsListView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/SessionsListView.swift#L80): `viewModel.selectedAgentName`
  - Replace with: same `reloadKey` task
  - Why: duplicate async trigger.
- [SessionsListView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/SessionsListView.swift#L83): `viewModel.fetchLimit`
  - Replace with: same `reloadKey` task
  - Why: duplicate async trigger.

### `aizen/Views/Chat/Components/ChatInputBar.swift`

- [ChatInputBar.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/ChatInputBar.swift#L273): `showingAttachmentPicker`
  - Replace with: open the panel directly from the button action, or pass an explicit `onPickAttachments` closure into `ChatInputBar`
  - Why: this boolean is functioning as a fire-once event flag. The view flips it back to `false` immediately after observing it.

### `aizen/Views/Chat/Components/InlineAutocompleteView.swift`

- [InlineAutocompleteView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/InlineAutocompleteView.swift#L107): `itemsVersion`
  - Keep
  - Why: scroll reset when the candidate list changes is an appropriate view effect.
- [InlineAutocompleteView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/InlineAutocompleteView.swift#L113): `selectedIndex`
  - Keep
  - Why: scroll-following selection.

### `aizen/Views/Chat/Components/ChatMessageList.swift`

- [ChatMessageList.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/ChatMessageList.swift#L265): `timelineSignature`
  - Keep
  - Why: this is the main imperative sync point from messages into the host controller.
- [ChatMessageList.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/ChatMessageList.swift#L272): `colorScheme`
  - Replace with: merge into one `.task(id: timelineStyleSignature)`
  - Why: it triggers the same work as the next six observers.
- [ChatMessageList.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/ChatMessageList.swift#L276): `markdownFontSize`
  - Replace with: merge into `timelineStyleSignature`
  - Why: duplicate style refresh path.
- [ChatMessageList.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/ChatMessageList.swift#L280): `markdownFontFamily`
  - Replace with: merge into `timelineStyleSignature`
  - Why: duplicate style refresh path.
- [ChatMessageList.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/ChatMessageList.swift#L284): `markdownParagraphSpacing`
  - Replace with: merge into `timelineStyleSignature`
  - Why: duplicate style refresh path.
- [ChatMessageList.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/ChatMessageList.swift#L288): `markdownHeadingSpacing`
  - Replace with: merge into `timelineStyleSignature`
  - Why: duplicate style refresh path.
- [ChatMessageList.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/ChatMessageList.swift#L292): `markdownContentPadding`
  - Replace with: merge into `timelineStyleSignature`
  - Why: duplicate style refresh path.
- [ChatMessageList.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/ChatMessageList.swift#L296): `effectiveTerminalThemeName`
  - Replace with: merge into `timelineStyleSignature`
  - Why: duplicate style refresh path.
- [ChatMessageList.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/ChatMessageList.swift#L3540): `currentThought`
  - Replace with: `.task(id: currentThought)` or compute rendered thought from the input if performance permits
  - Why: this is prop-to-cache mirroring. A small task is clearer, and if the markdown render is cheap enough the cached state can disappear entirely.

### `aizen/Views/Chat/Components/CompanionDivider.swift`

- [CompanionDivider.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/CompanionDivider.swift#L81): `effectiveThemeName`
  - Replace with: derived `dividerColor` computed property
  - Why: the cached color is a pure function of theme inputs. Local state plus `.onAppear` and `.onChange` is unnecessary unless profiling shows the parser is too expensive.

### `aizen/Views/Chat/Components/CompanionGitDiffView.swift`

- [CompanionGitDiffView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/CompanionGitDiffView.swift#L91): `gitStatus`
  - Replace with: merged `.task(id: summaryKey)` if `publishSummary()` grows or becomes async; otherwise keep
  - Why: currently acceptable, but it overlaps conceptually with `worktreePath` changes and can be consolidated.
- [CompanionGitDiffView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/CompanionGitDiffView.swift#L94): `worktreePath`
  - Replace with: same merged summary key
  - Why: same as above.

### `aizen/Views/Chat/Components/PlanApprovalDialog.swift`

- [PlanApprovalDialog.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/PlanApprovalDialog.swift#L264): `optionIdentityKey`
  - Replace with: `.task(id: optionIdentityKey)` or clamp `selectedIndex` inside the options update flow
  - Why: this is lifecycle-ish state normalization rather than an interactive side effect.

### `aizen/Views/Worktree/WorktreeDetailView.swift`

- [WorktreeDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeDetailView.swift#L625): `colorScheme`
  - Replace with: derived background color if feasible, otherwise keep
  - Why: this is pure theme derivation with a cached value.
- [WorktreeDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeDetailView.swift#L674): `selectedTab`
  - Keep
  - Why: persisting selected tab is a small side effect.
- [WorktreeDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeDetailView.swift#L678): `viewModel.selectedChatSessionId`
  - Keep, but consider merging the four session persistence observers through one helper
  - Why: persistence side effect is valid.
- [WorktreeDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeDetailView.swift#L682): `viewModel.selectedTerminalSessionId`
  - Keep, same reason.
- [WorktreeDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeDetailView.swift#L686): `viewModel.selectedBrowserSessionId`
  - Keep, same reason.
- [WorktreeDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeDetailView.swift#L690): `viewModel.selectedFileSessionId`
  - Keep, same reason.
- [WorktreeDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeDetailView.swift#L697): `showXcodeBuild`
  - Keep
  - Why: runtime option sync.

### `aizen/Views/Worktree/ActiveWorktreesView.swift`

- [ActiveWorktreesView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/ActiveWorktreesView.swift#L285): `activeWorktreeIDs`
  - Keep or move to `.task(id: activeWorktreeIDs)`
  - Why: this is a reasonable data refresh trigger, but not urgent.
- [ActiveWorktreesView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/ActiveWorktreesView.swift#L288): `selectedMode`
  - Replace with: custom picker binding setter
  - Why: this is a direct user-edit path.

### `aizen/Views/Worktree/WorktreeCreateSheet.swift`

- [WorktreeCreateSheet.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeCreateSheet.swift#L244): `initializeSubmodules`
  - Replace with: custom toggle binding setter
  - Why: direct user-edit path.
- [WorktreeCreateSheet.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeCreateSheet.swift#L249): `selectedSubmodulePaths`
  - Keep or merge into the same setter path used by the submodule picker
  - Why: if there is a single selection mutation point, this should live there.
- [WorktreeCreateSheet.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeCreateSheet.swift#L269): `mode`
  - Replace with: custom picker binding setter
  - Why: direct user-edit path.
- [WorktreeCreateSheet.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeCreateSheet.swift#L298): `branchName`
  - Replace with: custom text-field binding setter, potentially with debounced validation if the validator becomes expensive
  - Why: live validation belongs at the text mutation site.

### `aizen/Views/Worktree/Components/BranchSelectorView.swift`

- [BranchSelectorView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/BranchSelectorView.swift#L147): `searchText`
  - Replace with: custom binding setter or move filtering into a small view model
  - Why: direct search field input.

### `aizen/Views/Worktree/Components/WorktreeListItemView.swift`

- [WorktreeListItemView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/WorktreeListItemView.swift#L473): `selectedBranchForSwitch`
  - Replace with: selection callback from `BranchSelectorView`
  - Why: the optional selected branch is being used as a one-shot event, then nulled out. Use `onSelectBranch(_:)` and perform the switch directly.

### `aizen/Views/Worktree/Components/Git/GitPanelWindowContent.swift`

- [GitPanelWindowContent.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/GitPanelWindowContent.swift#L281): `gitStatus`
  - Replace with: `.task(id: gitStatusSignature)` if diff reload work stays async/debounced
  - Why: this observer is tied to downstream reload work and fits task-driven coordination.
- [GitPanelWindowContent.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/GitPanelWindowContent.swift#L287): `selectedHistoryCommit`
  - Replace with: `.task(id: selectedHistoryCommit?.id)` or equivalent identity key
  - Why: commit selection triggers async diff loading.
- [GitPanelWindowContent.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/GitPanelWindowContent.swift#L291): `selectedTab`
  - Keep
  - Why: runtime visibility sync is a small imperative effect.
- [GitPanelWindowContent.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/GitPanelWindowContent.swift#L604): `effectiveDiffOutput`
  - Keep or merge into the diff-load completion path
  - Why: comment validation is tied closely to diff replacement; if possible, validate at the source of diff updates rather than by observing the rendered output.

### `aizen/Views/Worktree/Components/Git/GitPanelWindowController.swift`

- [GitPanelWindowController.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/GitPanelWindowController.swift#L221): `selectedTab`
  - Keep
  - Why: lazily loading hosting info when entering the PR tab is a targeted side effect and a valid narrow observer.
- [GitPanelWindowController.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/GitPanelWindowController.swift#L226): `gitStatus.currentBranch`
  - Replace with: `.task(id: gitStatus.currentBranch)`
  - Why: this launches async PR status refresh work and should inherit cancellation semantics if the branch changes again.
- [GitPanelWindowController.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/GitPanelWindowController.swift#L266): `selectedBranchInfo`
  - Replace with: selection callback from `BranchSelectorView`
  - Why: the branch picker should switch branches directly instead of storing temporary selection state and observing it afterward.
- [GitPanelWindowController.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/GitPanelWindowController.swift#L376): `gitOperationService.isOperationPending`
  - Keep
  - Why: clearing local loading UI when a shared operation completes is a small, localized observer.

### `aizen/Views/Worktree/Components/Git/FileDiffSectionView.swift`

- [FileDiffSectionView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/FileDiffSectionView.swift#L58): `isExpanded`
  - Keep, or use `.task(id: isExpanded)` if load cancellation logic expands
  - Why: lazy section loading based on expansion is a valid localized side effect.

### `aizen/Views/Worktree/Components/Git/AllFilesDiffScrollView.swift`

- [AllFilesDiffScrollView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/AllFilesDiffScrollView.swift#L34): `scrollToFile`
  - Keep
  - Why: scroll request handling is a good `.onChange` use.

### `aizen/Views/Worktree/Components/Git/DiffView.swift`

- [DiffView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/DiffView.swift#L157): `scrollToFile`
  - Keep
  - Why: informs visible-file bookkeeping.

### `aizen/Views/Worktree/Components/Git/PullRequests/PullRequestDetailPane.swift`

- [PullRequestDetailPane.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/PullRequests/PullRequestDetailPane.swift#L42): `pr.id`
  - Replace with: `.task(id: pr.id)`
  - Why: resetting per-PR UI state when identity changes reads more naturally as task/lifecycle normalization.

### `aizen/Views/Worktree/Components/Git/Workflow/WorkflowRunDetailView.swift`

- [WorkflowRunDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/Workflow/WorkflowRunDetailView.swift#L67): `jobs`
  - Replace with: merged `.task(id: workflowSelectionKey)`
  - Why: this and `run.id` together define selected-job reset and initial selection behavior.
- [WorkflowRunDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/Workflow/WorkflowRunDetailView.swift#L73): `run.id`
  - Replace with: same merged task
  - Why: duplicate normalization path.

### `aizen/Views/Worktree/Components/Xcode/XcodeLogSheetView.swift`

- [XcodeLogSheetView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Xcode/XcodeLogSheetView.swift#L79): `buildManager.logOutput.count`
  - Keep
  - Why: auto-scroll on appended logs is an appropriate view side effect.

## Cross-Cutting Refactor Patterns

### 1. Replace event-flag state with explicit events

Apply to:

- `RootView.gitChangesContext`
- `ChatInputBar.showingAttachmentPicker`
- `WorktreeListItemView.selectedBranchForSwitch`
- `PostCreateActionsView.addActionRequested`
- `TerminalPaneView.voiceAction`
- `FileBrowserSessionView.fileToOpenFromSearch`

Preferred direction:

- callbacks for direct child-to-parent actions
- small coordinator objects for cross-window or cross-feature commands
- tokenized command structs when replay or identity matters

### 2. Replace async `.onChange` with `.task(id:)`

Apply to:

- `SessionsListView`
- `MCPMarketplaceView`
- `ANSIParser`
- `GitPanelWindowController` branch refresh
- `GitPanelWindowContent` diff-loading triggers
- `ChatSessionView` draft persistence
- `AgentDetailView`
- `WorkflowRunDetailView`
- `PullRequestDetailPane`

### 3. Move direct control writes into custom bindings

Apply to:

- `GeneralSettingsView`
- `TranscriptionSettingsView`
- `CustomAgentFormView`
- `SFSymbolPickerView`
- `WorktreeCreateSheet`
- `BranchSelectorView`
- `ActiveWorktreesView`

### 4. Merge duplicated style or normalization observers

Apply to:

- `ChatMessageList`
- `CommandPaletteWindowController`
- `ChatTabView`
- `WorkflowRunDetailView`
- `VVCodeSnippetView`
- `CodeEditorView`

## Suggested Implementation Order

1. Remove event-flag observers.
2. Replace async reload/search/load observers with `.task(id:)`.
3. Move picker/text-field related `.onChange` into binding setters.
4. Merge remaining repeated style/normalization observers.
5. Leave geometry/scroll/focus `.onChange` sites for last, and only change the ones that remain noisy after the higher-priority refactors.

## Expected Outcome

- Fewer feedback loops and selection cascades
- Better cancellation semantics for search, reload, parse, and diff work
- Fewer boolean and optional values used as one-shot command channels
- Clearer ownership boundaries between view state, user actions, and async loading
