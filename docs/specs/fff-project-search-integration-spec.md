# Aizen FFF Project Search Integration Spec

## Summary

Replace Aizen's custom repository file-search stack with `fff` and expand `⌘P` from filename-only lookup into a proper project search experience.

This spec covers:

- repository file search
- repository content search
- search result preview
- `@file` autocomplete reuse
- search indexing, ranking, and watcher lifecycle

This spec does **not** replace every search field in the app. `fff` should become the backend for repository-oriented search, not for generic UI filtering or command navigation.

## Current Problem

Today Aizen's search experience is split and too shallow:

- `⌘P` opens a dedicated file-search panel backed by `Features/Search/*`.
- the current implementation indexes files with `git ls-files` or manual filesystem walking and ranks them with a custom fuzzy scorer
- there is no first-class content search UI
- the same custom file index is reused by chat `@file` autocomplete
- result opening is path-only, so content matches cannot open directly to line/column

The net effect is that Aizen is good at "find a file by name" but weak at "find the place in the codebase where this thing is implemented."

## Goals

- make repository content search a first-class workflow, not a side feature
- preserve `⌘P` muscle memory for fast file opening
- use one backend for file search, content search, and `@file` autocomplete
- remove Aizen's custom file indexing and fuzzy-ranking implementation
- support live updates while repositories change
- support line/column-aware open flows for content matches
- keep the UI visually aligned with the existing Spotlight-style palette chrome

## Non-Goals

- replacing `⌘K` command palette navigation with `fff`
- replacing `searchable` filters in Settings, Workspace, Chat sessions, branch pickers, or other local lists
- replacing terminal in-buffer search
- building a semantic code search engine in this phase
- merging repository search and command palette into one shortcut in this phase

## Scope

### In Scope

- `Features/Search/*`
- `⌘P` worktree file search entry point
- new content-search entry point and UI
- shared repository-search backend for `UnifiedAutocompleteHandler`
- file-open flow updates needed for line/column navigation

### Out of Scope

- `App/CommandPalette/*`
- MCP registry search
- settings search
- workspace sidebar filtering
- chat session list filtering
- terminal search

## Investigation Findings

### Current Aizen Search Shape

Repository search is already isolated enough to migrate cleanly:

- `Features/Search/Application/FileSearchService.swift`
- `Features/Search/Application/FileSearchService+Indexing.swift`
- `Features/Search/Application/FileSearchService+Search.swift`
- `Features/Search/Application/FileSearchStore.swift`
- `Features/Search/UI/FileSearchWindowContent.swift`
- `Features/Worktree/UI/WorktreeDetailView+FileSearch.swift`
- `Features/Chat/Application/UnifiedAutocompleteHandler.swift`

Key constraints in the current implementation:

- the backend is fully custom
- search result rows are file-path rows only
- `FileBrowserStore.openFile(path:)` only accepts a file path
- `WorktreeDetailView` routes search selection by setting `fileToOpenFromSearch`

### Current Command Palette Is A Different System

`⌘K` is not repository search. It is workspace/worktree/tab/session navigation backed by `App/CommandPalette/*`.

That system should remain separate. Replacing it with `fff` would weaken the product boundary and misuse a repository search engine as a generic app navigation engine.

### FFF Fit For Aizen

`fff` is a strong fit for Aizen's repository search needs:

- fuzzy file search
- grep/content search
- query history and frecency
- git-aware ranking
- background scan and watcher support
- typed C API via `crates/fff-c`
- mixed search and parsed file locations

Important upstream findings:

- upstream workspace includes `crates/fff-c`, `crates/fff-core`, `crates/fff-mcp`, and Node packages
- `fff-c` exposes a generated `fff.h`
- `fff-c` already supports:
  - instance lifecycle
  - file search
  - directory search
  - mixed search
  - live grep
  - multi-grep
  - scan progress
  - watcher readiness
  - query tracking
  - git refresh
- search results include parsed location info
- grep results include line number, column, byte offset, match ranges, and context lines

### Aizen Build/Integration Feasibility

Aizen already has patterns that make native integration feasible:

- Xcode project already imports C modules via module map for `libgit2`
- app build already bundles native artifacts and resources
- `ProcessExecutor` exists if we need subprocess-based fallback or diagnostics

This means Aizen can integrate `fff` without inventing a novel build model.

## Product Decision

### Search Surface

Keep `⌘P` as the repository search shortcut, but evolve it into **Project Search** rather than a filename-only palette.

The search UI should have two primary modes:

- `Files`
- `Content`

Recommended entry points:

- `⌘P` opens Project Search in `Files` mode
- `⌘⇧F` opens the same Project Search panel in `Content` mode
- `Tab` switches between `Files` and `Content` while the panel is open

This preserves the current mental model while making content search first-class.

### Preview Layout

Adopt a split layout:

- left: results list
- right: preview

Recommended behavior:

- on wide layouts, show preview on the right
- on narrower layouts, collapse preview below or hide it behind a toggle
- default to the two-column layout on desktop-width windows/screens

This is the right direction for Aizen because the user intent is often "find and inspect before opening," especially for content matches.

### Result Semantics

In `Files` mode:

- each row is a file result
- preview shows the selected file in the existing editor renderer, configured read-only
- `Return` opens the file in the Files tab

In `Content` mode:

- each row is a content match
- row shows file path plus highlighted snippet
- preview centers on the selected match with surrounding context using the same editor renderer in read-only mode
- `Return` opens the file at the match line/column

### Keep `⌘K` Separate

Do not merge `⌘P` and `⌘K`.

Reason:

- `⌘K` is app/workspace navigation
- `⌘P` / `⌘⇧F` are repository search
- mixing them would overload ranking, UI copy, keyboard behavior, and mental model

Reuse chrome where useful, not behavior.

## UX Proposal

### Panel

- reuse the current Spotlight-style panel chrome (`LiquidGlassCard`, `SpotlightSearchField`, footer keycaps)
- rename the feature concept from "File Search" to "Project Search"
- increase default width beyond the current file-only palette to accommodate preview

Recommended initial panel size:

- about `960 x 600`

### Header

- search field at top
- segmented mode control for `Files` and `Content`
- in `Content` mode, a secondary control for grep mode:
  - `Plain`
  - `Regex`
  - `Fuzzy`

Default content mode:

- `Plain`

Persistence:

- remember the selected content grep submode per worktree/environment, not globally

### Files Mode

Behavior:

- empty query shows recent/frecency-ranked files
- typed query returns fuzzy-ranked file results from `fff`
- selected row drives preview
- preview is read-only, lazy-loaded, and reuses the existing full editor renderer

Nice-to-have later, not phase 1:

- optional directory results via mixed search

### Content Mode

Behavior:

- empty query shows guidance, not results
- typed query runs `fff_live_grep`
- results list is match-oriented, not file-oriented
- each row includes file name, relative path, and snippet
- preview centers on the selected match with highlights and context

Initial paging behavior:

- fetch a limited page of matches for fast first paint
- support incremental loading as the user scrolls

### Keyboard Behavior

- `↑` / `↓` move selection
- `Return` opens selected result
- `Esc` closes the panel
- `Tab` switches between `Files` and `Content`
- mode-specific shortcuts can be added after phase 1 if needed

### Open Behavior

Introduce a location-aware open request:

- path
- optional line
- optional column
- optional range

This replaces the current path-only contract for search-driven file opening.

## Architecture Proposal

### Ownership

Keep repository search ownership in `Features/Search/`.

Target shape:

```text
Features/Search/
├── Domain/
│   ├── ProjectSearchMode.swift
│   ├── ProjectSearchResult.swift
│   ├── ProjectSearchPreview.swift
│   ├── SearchOpenRequest.swift
│   └── SearchBackendProtocol.swift
├── Application/
│   ├── ProjectSearchStore.swift
│   ├── ProjectSearchCoordinator.swift
│   ├── FFFInstanceRegistry.swift
│   └── SearchPreviewLoader.swift
├── Infrastructure/
│   └── FFF/
│       ├── FFFBridge.swift
│       ├── FFFClient.swift
│       ├── FFFResultMapper.swift
│       ├── FFFDatabasePaths.swift
│       └── FFFBuildNotes.md
├── UI/
│   ├── ProjectSearchWindowController.swift
│   ├── ProjectSearchPanel.swift
│   ├── ProjectSearchWindowContent.swift
│   └── Components/
└── Testing/
```

### Backend Choice

Use `fff-c` via C FFI as the primary integration path.

#### Why `fff-c`

- official upstream C boundary already exists
- typed result structs already exist
- no custom IPC protocol needs to be invented
- lower latency than a helper-process JSON protocol
- better fit for interactive preview and autocomplete

#### Why Not Use `fff-mcp`

- MCP is the wrong abstraction for in-app interactive UI
- stdio/JSON roundtrips add avoidable overhead
- the app needs typed search and grep results, not tool-call semantics

#### Why Not Keep The Custom Backend

- it duplicates functionality that `fff` already handles better
- it does not solve content search
- it creates two ranking/indexing systems once grep is added

### Lifecycle Model

Create an `FFFInstanceRegistry` actor keyed by canonical worktree path.

Responsibilities:

- lazily create one `fff` instance per active worktree
- reuse the same instance across file search, content search, and `@file` autocomplete
- track last access time
- evict idle instances with LRU/TTL policy
- destroy instances cleanly when evicted

Recommended initial policy:

- lazy creation on first repository-search use
- cap warm instances to a small number, similar to the current cache behavior
- evict least-recently-used idle instances first

Rationale:

- Aizen can have many worktrees
- `fff` is designed as a long-running indexed engine
- we want warm indexes for active worktrees, not permanent watchers for every stored worktree

### FFF Configuration

Recommended initial configuration for active worktrees:

- `watch = true`
- `ai_mode = true`
- `enable_content_indexing = true`
- `enable_mmap_cache = true` for active project-search instances

Notes:

- this favors search quality and content-search performance
- UI must surface scan/warmup state because content indexing may continue after the first scan

### Persistence

Store `fff` databases under app support, namespaced by canonical worktree path hash:

- frecency db
- query history db

Store Project Search UI state separately from `fff` runtime data:

- last selected content grep submode per worktree/environment

Do not store `fff` runtime state in Core Data.

Core Data remains the source of truth for worktrees; `fff` runtime data is derived cache/state.

### Swift Bridge

Add a thin Swift wrapper around the C API.

Responsibilities:

- create/destroy instances
- convert C result structs into Swift domain models
- free all `fff` result objects correctly
- map file search, grep search, scan progress, and query tracking
- hide unsafe pointer handling from feature/application layers

The rest of Aizen should not deal with raw C pointers.

### Preview Rendering

Project Search preview should reuse the existing editor renderer rather than introducing a separate lightweight preview renderer in phase 1.

Reason:

- keeps rendering consistency with the Files tab
- reduces duplicate code paths for syntax highlighting and navigation behavior
- lets the search preview benefit from existing editor/runtime improvements

Constraint:

- preview must be configured read-only and loaded lazily so it does not regress palette responsiveness

### UI/Data Flow

#### Files Mode

1. `ProjectSearchStore` receives query changes
2. store asks `FFFInstanceRegistry` for worktree instance
3. `FFFClient.searchFiles(...)` calls `fff_search`
4. Swift models map into `ProjectSearchResult.file`
5. selected row triggers preview load
6. open action emits `SearchOpenRequest`

#### Content Mode

1. `ProjectSearchStore` receives query changes
2. store calls `FFFClient.liveGrep(...)`
3. Swift models map into `ProjectSearchResult.match`
4. selected row drives preview around match
5. open action emits `SearchOpenRequest` with line/column

#### Autocomplete

`UnifiedAutocompleteHandler` stops indexing files itself and asks the search backend for file results.

That keeps:

- one index
- one ranking model
- one watcher lifecycle

## Required Aizen Refactors

### Replace Path-Only Open Requests

The current search path goes through `fileToOpenFromSearch: String?`.

That is insufficient for content matches.

Replace it with a richer type, for example:

```swift
struct SearchOpenRequest: Equatable, Sendable {
    let path: String
    let line: Int?
    let column: Int?
    let endLine: Int?
    let endColumn: Int?
}
```

This request should flow from Search UI to Worktree/Files UI instead of raw string paths.

### Add Editor Navigation Support

The Files feature needs a way to:

- open a file
- move cursor/selection to line/column
- reveal the target range

If `VVCode` does not already expose enough navigation hooks, this must be added as part of the migration.

This is required for content search to feel complete.

### Rename File Search To Project Search

The current `FileSearch*` naming assumes file-name lookup only.

As part of the migration, rename the product surface and state ownership to `ProjectSearch*`.

This avoids leaving content grep trapped in file-only types.

## Build And Packaging Plan

### Source Of Truth

Pin `fff` to a specific upstream commit or release, not floating `main`.

Recommended approach:

- vendor integration metadata in the repo
- pin one upstream commit
- document the pinned version in the build script and spec

### Build Integration

Add a build script for `fff-c`, similar in spirit to other native integrations already present in Aizen.

Recommended artifacts:

- `libfff_c.dylib`
- generated `fff.h`
- local `module.modulemap`

Recommended repo placement:

- `Vendor/fff-c/include/fff.h`
- `Vendor/fff-c/include/module.modulemap`
- built dylib copied into the app bundle during Xcode build

### Build Requirements

Building from source will require Rust tooling in addition to current requirements.

Update build docs to include:

- `rustup`
- stable Rust toolchain
- cargo

End-user app builds can still ship prebuilt bundled artifacts; this requirement is mainly for source builds and CI.

### Codesigning And Release

The release pipeline must:

- build the dylib for the app target architecture
- bundle it into the app
- codesign it with the app bundle
- include it in notarized release artifacts

## Rollout Plan

### Phase 1: Infrastructure

- add pinned `fff-c` integration
- add module map and Swift bridge
- add `FFFInstanceRegistry`
- add test coverage for wrapper lifecycle and result mapping

### Phase 2: New Search Backend

- implement `SearchBackendProtocol`
- migrate file search queries from `FileSearchService` to `fff`
- keep current file-search UI shape temporarily if needed
- add query tracking on open

### Phase 3: New Project Search UI

- replace file-only store/UI with `ProjectSearchStore`
- add `Files` and `Content` modes
- add preview pane
- wire `⌘⇧F` to open the same panel in content mode
- keep this as a Spotlight-style floating panel in phase 1

### Phase 4: Files Open Navigation

- replace path-only open request flow
- add line/column open support in Files feature
- wire content results to editor navigation

### Phase 5: Autocomplete Migration

- move `UnifiedAutocompleteHandler` to the shared search backend
- remove direct use of `FileSearchService`

### Phase 6: Cleanup

- delete old custom indexing and fuzzy scoring implementation
- remove dead cache code
- rename feature/product surface from `FileSearch` to `ProjectSearch`

Deferred beyond the core migration:

- mixed file+directory results in `Files` mode
- deeper integration of search directly into the Files feature UI

## Acceptance Criteria

- `⌘P` returns `fff`-ranked file results for the current worktree
- `⌘⇧F` opens the same panel in content mode
- content results show snippets and open at line/column
- preview pane updates with current selection
- chat `@file` autocomplete uses the same `fff`-backed index
- current custom `FileSearchService` indexing/scoring code is removed
- `⌘K` command palette behavior remains unchanged
- non-repository search fields in Settings/Workspace/Chat remain unchanged

## Risks

### Build Complexity

Adding Rust to the build pipeline is a real cost.

Mitigation:

- keep the integration narrow
- pin upstream
- automate artifact build/copy/sign steps

### In-Process Native Crash Risk

`fff-c` runs in-process, so a native bug could affect the app.

Mitigation:

- keep Swift bridge minimal
- add wrapper tests
- keep the old backend behind a temporary fallback during rollout if needed

### Memory/Watcher Pressure Across Many Worktrees

Aizen can keep many worktrees around.

Mitigation:

- registry-based lazy instance lifecycle
- eviction policy for inactive worktrees

### Editor Navigation Gap

Content search is not complete unless the editor can open directly to a match.

Mitigation:

- treat location-aware open requests as part of the core migration, not optional polish

## Resolved Decisions

- preview reuses the full existing editor renderer in read-only mode
- content grep submode persistence is per worktree/environment
- mixed file+directory results are deferred; phase 1 remains a Spotlight-style search panel, with deeper Files integration considered later

## Recommendation

Proceed with `fff-c` integration and a unified Project Search panel with:

- `⌘P` for files
- `⌘⇧F` for content
- left results, right preview
- one shared `fff` backend per active worktree

This gives Aizen the biggest practical improvement with the cleanest architecture change and avoids turning repository search into yet another custom subsystem.
