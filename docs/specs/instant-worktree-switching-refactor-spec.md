# Instant Worktree Switching Refactor

## Summary

Refactor Aizen's worktree and project switching path so switching between recently-used worktrees feels immediate while still restoring the user's prior UI state.

The current architecture restores the right state, but it does so by recreating the detail subtree for the next worktree and letting each feature bootstrap itself again from persistence and runtime state. That keeps behavior correct, but it puts too much work on the critical path of a switch.

This refactor introduces:

- one long-lived scene owner per warm worktree
- warm child-scene reuse for chat, terminal, files, and browser inside a worktree
- in-memory restoration for recent worktrees
- persistence as cold-start fallback rather than switch-time source of truth
- explicit warm vs cold switch behavior
- background hydration and refresh after first paint
- bounded scene caching and eviction rules

## Problem Statement

Switching worktrees is currently conceptually simple but operationally expensive:

1. navigation selection changes
2. the previous detail subtree disappears
3. a new `WorktreeDetailView` is created for the target worktree
4. tab, session, browser, file, chat, git, and Xcode state is restored by feature-local logic
5. expensive runtime work starts during or immediately after view creation

The result is that the app restores the correct state, but the user waits for reconstruction work that should not be on the switch path.

The main issue is not that state is persisted incorrectly. The issue is that persistence is acting as the active switching mechanism instead of a fallback recovery mechanism.

For recent worktrees, the switch path should be an in-memory scene activation, not a subtree rebuild.

The same principle also applies one level lower inside a worktree:

- switching top-level tabs should not behave like closing one feature and reopening another
- switching chat sessions should not behave like cold-booting the selected conversation
- switching browser tabs should not destroy and recreate the selected tab's live browser runtime if it can be reused
- switching terminal sessions should reuse existing terminal runtime ownership and avoid unnecessary controller rebuilds where practical

## Evidence From Current Code

### 1. Detail view identity is recreated on every worktree switch

[AppNavigationDetailColumn.swift](/Users/uyakauleu/development/aizen/aizen/App/Navigation/AppNavigationDetailColumn.swift#L21) creates a new `WorktreeDetailView` for the selected worktree and applies `.id(worktree.id)` in both normal and cross-project cases at:

- [AppNavigationDetailColumn.swift](/Users/uyakauleu/development/aizen/aizen/App/Navigation/AppNavigationDetailColumn.swift#L34)
- [AppNavigationDetailColumn.swift](/Users/uyakauleu/development/aizen/aizen/App/Navigation/AppNavigationDetailColumn.swift#L51)

That guarantees structural identity changes for the whole detail subtree whenever the selected worktree changes.

This means the following view-owned state is recreated on switch:

- `WorktreeDetailStore`
- `FileBrowserStore`
- `BrowserSessionStore`
- selected tab state inside `WorktreeDetailView`
- feature-local `@StateObject` and `@State` owned under the detail tree

### 2. Worktree detail attach performs runtime work immediately

[WorktreeDetailView+Lifecycle.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/WorktreeDetailView+Lifecycle.swift#L69) handles worktree identity changes by:

- loading tab state
- validating selected tab
- attaching the worktree runtime

The attach step calls:

- [WorktreeRuntime.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/Application/WorktreeRuntime.swift#L63)

`attachDetail(showXcode:)` then:

- ensures a watcher
- refreshes Git summary state
- performs Xcode visibility sync

The refresh is currently triggered directly from detail attachment:

- [WorktreeRuntime.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/Application/WorktreeRuntime.swift#L72)
- [WorktreeRuntime.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/Application/WorktreeRuntime.swift#L73)
- [WorktreeRuntime.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/Application/WorktreeRuntime.swift#L74)

### 3. Warm runtime retention exists, but only at the Git/Xcode layer

[WorktreeRuntimeCoordinator.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/Application/WorktreeRuntimeCoordinator.swift#L13) already caches `WorktreeRuntime` by worktree path and keeps runtimes alive for a short idle TTL:

- [WorktreeRuntimeCoordinator.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/Application/WorktreeRuntimeCoordinator.swift#L9)

This helps Git, diff, workflow, and Xcode state reuse, but it does not solve switching latency because the detail scene and feature stores are still recreated on every switch.

### 4. Chat activation still boots heavy work on selection

[ChatSessionView+Lifecycle.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/UI/ChatSessionView+Lifecycle.swift#L50) runs `viewModel.setupAgentSession()` whenever the selected chat becomes active.

[ChatSessionStore+Bootstrap.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/Application/ChatSessionStore+Bootstrap.swift#L17) does all of the following on setup:

- timeline reset
- pending attachment load
- historical message load
- autocomplete worktree indexing
- bind to existing agent session if cached
- otherwise create and start or resume a new ACP session

The in-memory ACP session cache in:

- [ChatSessionRegistry.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/Application/ChatSessionRegistry.swift#L16)
- [ChatSessionRegistry+SessionCache.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/Application/ChatSessionRegistry+SessionCache.swift#L38)

is useful, but it is scoped to chat sessions rather than whole worktree scenes, and the surrounding view-model work still reruns on switch.

### 5. File browser restoration eagerly reopens all previously open files

[FileBrowserStore+SessionPersistence.swift](/Users/uyakauleu/development/aizen/aizen/Features/Files/Application/FileBrowserStore+SessionPersistence.swift#L13) restores file browser state from `FileBrowserSession`.

When open files exist, it immediately loops through all saved paths and reopens them:

- [FileBrowserStore+SessionPersistence.swift](/Users/uyakauleu/development/aizen/aizen/Features/Files/Application/FileBrowserStore+SessionPersistence.swift#L32)
- [FileBrowserStore+SessionPersistence.swift](/Users/uyakauleu/development/aizen/aizen/Features/Files/Application/FileBrowserStore+SessionPersistence.swift#L35)

That is correct behavior for restoration, but it is too expensive to place directly on the switch path.

### 6. Browser state is recreated with the view and drops active WebView ownership

[BrowserTabView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Browser/UI/BrowserTabView.swift#L13) creates a new `BrowserSessionStore` in `init`.

[BrowserSessionStore.swift](/Users/uyakauleu/development/aizen/aizen/Features/Browser/Application/BrowserSessionStore.swift#L28) immediately calls `loadSessions()`, which is currently implemented in:

- [BrowserSessionStore+Sessions.swift](/Users/uyakauleu/development/aizen/aizen/Features/Browser/Application/BrowserSessionStore+Sessions.swift#L9)

When a browser session becomes active, the store resets active WebView state:

- [BrowserSessionStore+Sessions.swift](/Users/uyakauleu/development/aizen/aizen/Features/Browser/Application/BrowserSessionStore+Sessions.swift#L87)
- [BrowserSessionStore+Sessions.swift](/Users/uyakauleu/development/aizen/aizen/Features/Browser/Application/BrowserSessionStore+Sessions.swift#L94)

And the view only keeps the active tab alive:

- [BrowserTabView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Browser/UI/BrowserTabView.swift#L48)

That is a reasonable tab-memory optimization, but when the entire browser scene is recreated on worktree switch the active browser state still cold-starts.

### 7. File and browser stores are view-owned rather than worktree-scoped

[FileBrowserSessionView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Files/UI/FileBrowserSessionView.swift#L17) creates `FileBrowserStore` as a `@StateObject`.

[BrowserTabView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Browser/UI/BrowserTabView.swift#L11) creates `BrowserSessionStore` as a `@StateObject`.

That makes their lifetime a function of SwiftUI subtree identity rather than a function of the selected worktree's lifecycle.

### 8. Chat only keeps one selected session mounted

[ChatTabView+CompanionLayout.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/UI/ChatTabView+CompanionLayout.swift#L21) intentionally keeps only cached selected chat sessions mounted, and [ChatTabView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/UI/ChatTabView.swift#L22) sets `maxCachedSessions = 1`.

That is a good optimization inside one worktree, but there is no equivalent worktree-level scene cache above it.

### 9. Top-level worktree tab switching destroys the previous feature subtree

[WorktreeDetailView+Content.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/WorktreeDetailView+Content.swift#L27) renders top-level worktree content as one `if / else if` chain over:

- chat
- terminal
- files
- browser

See:

- [WorktreeDetailView+Content.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/WorktreeDetailView+Content.swift#L30)
- [WorktreeDetailView+Content.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/WorktreeDetailView+Content.swift#L38)
- [WorktreeDetailView+Content.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/WorktreeDetailView+Content.swift#L46)
- [WorktreeDetailView+Content.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/WorktreeDetailView+Content.swift#L51)

That means switching from one top-level tab to another destroys the previous feature subtree unless that feature has its own separate runtime cache below the view layer.

### 10. Chat session switching intentionally evicts all but the active chat view

[ChatTabView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/UI/ChatTabView.swift#L25) stores only `cachedSessionIds`, and [ChatTabView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/UI/ChatTabView.swift#L27) caps the cache at one selected session.

[ChatTabView+SessionActions.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/UI/ChatTabView+SessionActions.swift#L17) updates the cache on session selection and trims older entries at:

- [ChatTabView+SessionActions.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/UI/ChatTabView+SessionActions.swift#L22)

The selected chat view then performs selection-time setup at:

- [ChatSessionView+Lifecycle.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/UI/ChatSessionView+Lifecycle.swift#L50)
- [ChatSessionView+Lifecycle.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/UI/ChatSessionView+Lifecycle.swift#L53)

So switching between two recently-used chat sessions can still feel cold even though ACP session state may be cached.

### 11. Browser tab switching recreates the active WebView layer

[BrowserTabView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Browser/UI/BrowserTabView.swift#L48) keeps only the active browser content alive and applies:

- [BrowserTabView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Browser/UI/BrowserTabView.swift#L78)

to the `WebViewWrapper`.

At the store layer, selecting a browser session resets active browser runtime state:

- [BrowserSessionStore+Sessions.swift](/Users/uyakauleu/development/aizen/aizen/Features/Browser/Application/BrowserSessionStore+Sessions.swift#L87)
- [BrowserSessionStore+Sessions.swift](/Users/uyakauleu/development/aizen/aizen/Features/Browser/Application/BrowserSessionStore+Sessions.swift#L94)

That makes browser tab switching a likely source of perceived slowness even within one worktree.

### 12. Terminal session switching is partially protected, but the controller layer is still recreated

[TerminalTabView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Terminal/UI/TerminalTabView.swift#L28) only renders the selected terminal session.

[SplitTerminalView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Terminal/UI/Components/SplitTerminalView.swift#L21) owns a `TerminalSplitController` as a `@StateObject`, so the controller is recreated when the selected terminal subtree is recreated.

This is less severe than browser or chat because terminal surfaces are already cached in:

- [TerminalRuntimeStore.swift](/Users/uyakauleu/development/aizen/aizen/Features/Terminal/Application/TerminalRuntimeStore.swift#L19)
- [TerminalRuntimeStore+Cache.swift](/Users/uyakauleu/development/aizen/aizen/Features/Terminal/Application/TerminalRuntimeStore+Cache.swift#L4)

and `TerminalPaneView` can recover an existing surface at:

- [TerminalPaneView+SurfaceLifecycle.swift](/Users/uyakauleu/development/aizen/aizen/Features/Terminal/UI/Components/TerminalPaneView+SurfaceLifecycle.swift#L13)

But the session-level controller and layout ownership is still tied to subtree lifetime rather than to terminal-session lifetime.

### 13. File tab switching recreates the file browser store and tree listing work

[FileBrowserSessionView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Files/UI/FileBrowserSessionView.swift#L12) owns `FileBrowserStore` as a `@StateObject`, so leaving and re-entering the files tab recreates the store unless the entire worktree scene stays warm.

[FileBrowserStore+SessionPersistence.swift](/Users/uyakauleu/development/aizen/aizen/Features/Files/Application/FileBrowserStore+SessionPersistence.swift#L32) still reopens saved file paths during restore.

The tree itself also performs synchronous directory listing in view body recursion:

- [FileTreeView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Files/UI/Components/FileTreeView.swift#L37)
- [FileBrowserStore+DirectoryListing.swift](/Users/uyakauleu/development/aizen/aizen/Features/Files/Application/FileBrowserStore+DirectoryListing.swift#L11)

That makes the files tab another likely contributor to perceived slowness when re-entered cold.

## Goals

- Switching to a recently-used worktree should feel immediate.
- State restoration for recent worktrees should come from in-memory scene ownership, not from rebuilding feature stores.
- Switching top-level tabs inside a worktree should reuse warm feature scenes where possible.
- Switching between recent chat sessions should not require cold chat bootstrap.
- Switching between recent browser tabs should reuse live browser runtime state where possible.
- Terminal session switches should reuse live terminal surfaces and minimize controller reconstruction.
- Persisted state should remain the recovery source for cold start, process relaunch, and evicted scenes.
- Worktree switching should not synchronously trigger:
  - ACP session start or resume
  - eager reopen of every file tab
  - browser store reconstruction
  - new WKWebView creation unless the browser scene was cold
  - Git summary refresh unless the cached runtime is stale
  - Xcode project detection unless stale or uncached
- Warm top-level tab switches should not synchronously trigger cold file tree restore, browser tab restore, or chat setup for already-warm child scenes.
- The architecture should stay feature-first and avoid new app-global vague manager types.
- The design should support bounded memory usage with explicit scene eviction.

## Non-Goals

- Rewriting every feature's internal state model in one pass.
- Making every hidden worktree fully live forever.
- Keeping all browser tabs and all terminal surfaces mounted without bounds.
- Redesigning the worktree UI.
- Changing persisted Core Data schema unless it becomes necessary for a later phase.

## Product Principles

Recent worktrees should behave like suspended scenes, not like closed documents.

That means:

- restore instantly from memory when warm
- paint from snapshot when cold
- reconcile runtime state after paint
- never put heavy reconstruction work directly on the selection path

Persistence remains necessary, but it should not be the mechanism that makes switching work during a warm app session.

## Proposed Architecture

### 1. Introduce `WorktreeSceneRegistry`

Suggested location:

- `aizen/Features/Worktree/Application/WorktreeSceneRegistry.swift`

Responsibilities:

- own a bounded cache of warm worktree scenes
- return the scene for a worktree synchronously on switch
- manage LRU ordering
- evict cold scenes according to explicit policy
- coordinate scene activation and deactivation

This type should be `@MainActor` because it owns UI-facing scene objects and integrates with SwiftUI navigation state.

### 2. Introduce `WorktreeSceneStore`

Suggested location:

- `aizen/Features/Worktree/Application/WorktreeSceneStore.swift`

Responsibilities:

- own all worktree-scoped UI and application state needed for instant restore
- be the long-lived owner for the selected worktree's feature stores
- expose lightweight scene snapshot state for switching and persistence

Suggested owned state:

- selected tab
- selected chat session id
- selected terminal session id
- selected browser session id
- selected file session id
- `WorktreeRuntime`
- `WorktreeDetailStore`
- `FileBrowserStore`
- `BrowserSessionStore`
- worktree-local chat scene coordinator or cache
- any other worktree-local transient state that should survive switches

Important rule:

- `WorktreeSceneStore` owns feature stores
- SwiftUI views observe those stores
- views no longer define store lifetime

### 3. Add child-scene caches inside each worktree scene

`WorktreeSceneStore` should not only remember which top-level tab is selected. It should also own warm child-scene state for the major feature areas inside a worktree.

Suggested owned child-scene state:

- one warm files scene per worktree
- one warm browser scene per worktree with small per-browser-session runtime reuse
- a bounded chat session scene cache per worktree
- a bounded terminal session controller cache per worktree

This does not mean every child scene must stay fully mounted forever. It means child-scene lifetime should be owned by the worktree scene rather than by transient `if / else if` view identity.

#### Chat child-scene policy

- keep the selected chat scene warm
- keep 1 to 2 additional recent chat session scenes warm
- separate "bind to warm chat scene" from "cold bootstrap ACP/history/indexing"

#### Browser child-scene policy

- keep browser session metadata warm for the worktree
- reuse selected tab `WKWebView` when possible
- optionally keep a small LRU of recent `WKWebView` instances per worktree
- do not null out warm browser runtime state on every tab switch unless eviction requires it

#### Terminal child-scene policy

- continue using `TerminalRuntimeStore` for Ghostty surface reuse
- add optional caching for `TerminalSplitController` per `TerminalSession`
- treat terminal session switching as session activation, not controller recreation, when still warm

#### Files child-scene policy

- keep one warm `FileBrowserStore` per worktree
- retain open file tab metadata and selected file state while the worktree scene is warm
- move expensive tree and file reopening work off the critical path

### 4. Split warm-switch state from cold-start persistence

Current behavior mixes these two concepts:

- persisted tab or session identity
- active in-memory feature state

The new design should separate them explicitly.

#### Warm scene source of truth

For a scene still present in `WorktreeSceneRegistry`:

- selected tab comes from `WorktreeSceneStore`
- file browser open files come from `FileBrowserStore`
- browser sessions come from `BrowserSessionStore`
- selected chat session and any draft state come from the scene's chat ownership

#### Cold scene source of truth

If a scene is not present in memory:

- use `WorktreeTabStateStore`
- use Core Data-backed file and browser session state
- use cached chat session metadata and `ChatSessionRegistry` if available
- create a new `WorktreeSceneStore`
- hydrate it in phases

Persistence is therefore used to rebuild a scene only when the scene is absent.

### 5. Add explicit warm and cold switch behavior

#### Warm switch

Warm switch should:

1. resolve scene synchronously from `WorktreeSceneRegistry`
2. set active scene id
3. render the already-owned scene immediately
4. schedule background refresh only if stale

Warm switch must not wait on feature bootstrapping.

Warm child-scene switch should follow the same rule:

- top-level tab switch should activate an existing child scene when warm
- chat session switch should bind to an existing warm chat scene when available
- browser tab switch should reuse warm `WKWebView` state when available
- terminal session switch should reuse warm surface and controller state when available

#### Cold switch

Cold switch should:

1. allocate a `WorktreeSceneStore`
2. synchronously apply a minimal snapshot:
   - selected tab
   - selected session ids
   - file selection
   - browser tab metadata
3. paint immediately
4. hydrate heavy feature state after paint

Cold switch can be slightly slower than warm switch, but it should still paint from metadata quickly rather than waiting on complete restoration.

### 6. Change the detail column to host scenes, not recreate them

`AppNavigationDetailColumn` should stop making worktree switching equivalent to creating a new `WorktreeDetailView` identity.

The new model should be:

- navigation selection chooses the active scene
- the detail column renders a scene host
- the scene host binds to a cached `WorktreeSceneStore`

Required rule:

- do not force subtree recreation for a warm worktree switch with `.id(worktree.id)`

If a new identity boundary is required, it should exist at scene allocation time rather than on every selection change.

### 7. Move feature store lifetime out of view init

The following stores should stop being created directly in SwiftUI view init:

- `FileBrowserStore`
- `BrowserSessionStore`
- any future worktree-scoped chat coordinator that should survive switches
- any terminal-session-scoped controller that should survive switching between sessions

Views should receive those stores from `WorktreeSceneStore` or a scene-scoped coordinator.

This aligns with the feature-first architecture rules already used elsewhere in the app:

- `Application` owns state and orchestration
- `UI` observes and presents

### 8. Introduce phased hydration for files and browser

#### File browser

Current eager reopen of every file is too expensive for switch-time restoration.

New policy:

- restore open file tab metadata immediately
- load selected file contents first
- load other open file contents lazily after paint
- do not block switch on hidden file tabs

#### Browser

New policy:

- restore browser session list and selected session metadata immediately
- reuse existing active `WKWebView` if the scene is warm
- reuse the selected browser tab runtime on tab switch when still warm
- if cold, instantiate only the selected browser content first
- background-hydrate non-selected browser state as needed

### 9. Narrow chat work on switch

Current chat setup is doing both:

- view-model binding work
- session boot or resume work

Those concerns should be separated.

New policy:

- on warm switch:
  - bind to existing `ChatSessionStore` or scene-owned chat coordinator
  - do not restart setup if the selected chat scene is already warm
- on warm chat-session switch:
  - prefer switching to a retained chat scene over recreating a new `ChatSessionView` subtree
  - do not rerun unnecessary history fetch, autocomplete indexing, or ACP setup for recent sessions
- on cold switch:
  - restore selected chat id and persisted draft immediately
  - attach historical timeline snapshot
  - start ACP resume or reindex work after first paint

ACP session ownership can remain in `ChatSessionRegistry`, but the switch path should not depend on doing new ACP work before the user sees the scene.

### 10. Add explicit scene snapshot types

Suggested types:

- `WorktreeSceneSnapshot`
- `FileBrowserSceneSnapshot`
- `BrowserSceneSnapshot`
- `ChatSceneSnapshot`
- `TerminalSessionSceneSnapshot`

These should be lightweight, immutable value types used for:

- warm scene bookkeeping
- cold scene hydration
- instrumentation
- tests

They are not a replacement for live stores. They are the transport format for quick restore and verification.

## Activation and Refresh Rules

### Scene activation

When a scene becomes active:

- make it visible immediately
- mark it as recently used
- attach cheap visibility observers if not already attached
- refresh only stale runtime data in background
- preserve warm child-scene ownership unless eviction policy requires teardown

### Scene deactivation

When a scene becomes inactive:

- keep in-memory UI state intact
- stop work that must only run for visible scenes
- keep cached stores available for quick reuse

### Runtime refresh

Runtime refresh should use explicit freshness windows.

Suggested initial policy:

- Git summary:
  - reuse if fresh
  - refresh on stale or known mutation
- diff:
  - refresh only when a visible diff consumer exists
- Xcode detection:
  - reuse project detection if cached
  - do not redetect on every warm switch
- ACP:
  - do not resume/start on warm scene activation unless the selected chat scene is actually cold or disconnected

## Eviction Rules

Scene caching must be bounded.

Suggested initial policy:

- keep the active scene plus the 2 to 4 most recent inactive scenes warm
- evict least-recently-used scenes under memory pressure or when exceeding the scene count limit
- evict browser-heavy scenes more aggressively if needed
- keep persisted metadata for all scenes even after in-memory eviction

Eviction should remove:

- scene-owned UI stores
- browser WebView ownership
- any worktree-scoped transient caches owned only by the scene

Eviction should not remove:

- persisted tab/session identity
- persisted file/browser metadata
- chat session persistence records
- worktree runtime if it is still independently retained by another visible surface

## Migration Plan

### Phase 1: Scene ownership

Create:

- `WorktreeSceneRegistry`
- `WorktreeSceneStore`
- scene host wiring in the detail column

Behavior target:

- warm recent worktrees no longer rebuild feature stores on switch

### Phase 2: Top-level tab warm switching

Refactor:

- worktree tab switching so child feature scenes can stay warm
- files and browser tab ownership so switching away and back does not cold-recreate them by default

Behavior target:

- switching chat, terminal, files, and browser tabs inside one warm worktree no longer behaves like full subtree teardown

### Phase 3: Move file and browser state into scene ownership

Refactor:

- `FileBrowserStore` lifetime
- `BrowserSessionStore` lifetime
- browser session runtime reuse

Behavior target:

- file and browser state survives worktree switches while scene is warm
- browser tab switches reuse warm browser runtime state where possible

### Phase 4: Chat switch-path narrowing

Refactor:

- separate chat bind-from-scene from chat cold bootstrap
- keep recent chat session state warm per scene

Behavior target:

- switching back to a recent worktree with a selected chat does not rerun unnecessary chat bootstrap work
- switching between recent chat sessions is mostly a warm scene activation

### Phase 5: Terminal session controller warming

Refactor:

- preserve `TerminalSplitController`-level state for recent terminal sessions where useful
- keep relying on `TerminalRuntimeStore` for Ghostty surface reuse

Behavior target:

- terminal session switches remain mostly warm and avoid avoidable controller reconstruction work

### Phase 6: Lazy hydration and snapshot polish

Add:

- selected-first file hydration
- cold scene snapshots
- post-paint hydration instrumentation

Behavior target:

- cold switches paint quickly even when full scene hydration continues in background

### Phase 7: Tuning and memory policy

Tune:

- scene cache size
- browser retention behavior
- runtime freshness windows
- eviction heuristics

Behavior target:

- switching remains fast without unbounded memory growth

## Instrumentation Requirements

This refactor should be measured, not judged only by feel.

Add timing and counters for:

- selection-to-first-paint for warm switch
- selection-to-interactive for warm switch
- selection-to-first-paint for cold switch
- top-level tab-switch first-paint
- chat-session-switch first-paint
- browser-tab-switch first-paint
- terminal-session-switch first-paint
- scene cache hit rate
- scene eviction count
- file lazy hydration count and duration
- browser WebView reuse count
- chat bootstrap count on worktree switch
- chat bootstrap count on chat-session switch
- Git summary refresh count caused by worktree switch
- Xcode detection count caused by worktree switch
- terminal controller recreation count
- synchronous file tree listing count during files-tab activation

## Acceptance Criteria

### Functional

- Switching worktrees preserves the previously active tab and selected session ids.
- Warm worktree switches preserve file browser, browser, and chat scene state without reconstructing feature stores.
- Warm top-level tab switches preserve feature-scoped state without reconstructing the entire selected feature subtree.
- Recent chat session switches preserve conversation scene state without unnecessary cold bootstrap.
- Recent browser tab switches reuse live browser runtime state when still warm.
- Cold worktree switches still restore persisted state correctly.
- Scene eviction does not lose persisted state.

### Performance

- Warm switch paints from memory without waiting on file reopen loops, browser session reload, or ACP startup.
- Warm switch does not trigger eager full feature bootstrap on the critical path.
- Warm top-level tab switch does not synchronously rebuild cold child scenes for files, browser, or chat when those child scenes are still warm.
- Browser tab switch avoids unnecessary `WKWebView` recreation when the selected browser tab is warm.
- Chat session switch avoids unnecessary setup work for recent warm sessions.
- Cold switch paints a minimal restored scene before heavy hydration completes.

### Architectural

- Worktree-scoped feature store lifetime is owned by `Application`, not by SwiftUI view init.
- Persistence is not the primary source of truth for recent in-memory worktree switches.
- The detail navigation layer activates cached scenes rather than forcing subtree recreation.

## Risks and Tradeoffs

### 1. Higher memory usage

Keeping recent worktree scenes warm increases memory usage, especially for:

- browser scenes
- file content buffers
- chat timeline state
- terminal-related UI ownership

This is acceptable only with explicit cache bounds and eviction.

### 2. More lifetime complexity

Scene caching adds a new lifetime layer between navigation state and feature stores.

That complexity is justified because the current design places too much cost on worktree switching.

### 3. Mixed warm and cold behavior

The app must behave correctly whether a scene is:

- active
- warm but hidden
- evicted
- cold-started after relaunch

This requires clear ownership and tests around transition boundaries.

## Open Questions

- Should `WorktreeSceneRegistry` keep scenes by worktree id, worktree path, or both?
- Should browser scenes keep one active `WKWebView` only, or a small per-scene tab cache?
- Should terminal UI ownership remain separate from worktree scene ownership because terminal surface lifetime is already partly runtime-cached?
- Should the worktree runtime and worktree scene share one eviction policy or separate ones?
- Do we want an explicit placeholder or skeleton for cold scene hydration, or should we always paint from the latest minimal snapshot?

## Recommended First Implementation

The first cut should be intentionally narrow:

1. add `WorktreeSceneRegistry`
2. add `WorktreeSceneStore`
3. stop forcing detail subtree recreation on warm switch
4. move `FileBrowserStore` and `BrowserSessionStore` under scene ownership
5. treat top-level tab switches as child-scene activation rather than transient `if / else if` teardown
6. leave chat ACP ownership in `ChatSessionRegistry`, but stop making worktree switch depend on cold chat bootstrap

That slice is large enough to materially improve switch latency and small enough to ship incrementally without rewriting every feature at once.
