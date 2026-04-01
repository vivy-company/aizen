# Concurrency Boundary Refactor

## Summary

Aizen does not have a general “too many actors” problem.

It has a smaller but more important problem: a handful of actor and `@MainActor` types own the wrong responsibilities, then compensate with `nonisolated`, `Task.detached`, or mixed sync/async APIs.

This spec expands the earlier narrow `nonisolated` review into a broader concurrency boundary cleanup.

The goal is not to remove actors.

The goal is to make actor and main-actor boundaries honest:

- actors own serialized mutable state and side effects
- `@MainActor` types own UI-observable state and coordination only
- pure parsing, query, command-building, and persistence helpers live outside those boundaries
- synchronous reads come from snapshots or plain helpers, not isolation escape hatches

## Project Context

The app target uses:

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

That makes isolation design especially important:

- app types are main-actor isolated by default unless explicitly moved off
- `nonisolated` on app-side actor or `@MainActor` types is a real escape hatch
- heavy work should not stay attached to UI-owned types by default

## What Looks Healthy Today

These patterns are fine and should not drive a broad rewrite:

- domain actors that wrap stateful external systems or serialized side effects
- `@MainActor` observable stores that primarily publish UI state
- static or pure helper functions marked `nonisolated` only because they do not touch isolated state
- delegate callbacks that must be nonisolated and immediately hop back to the right actor

Examples that look broadly healthy:

- [GitIndexWatchCenter.swift](/Users/uyakauleu/development/aizen/aizen/Utilities/GitIndexWatchCenter.swift)
- [GitStatusService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/Domain/GitStatusService.swift)
- [GitBranchService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/Domain/GitBranchService.swift)
- [GitRemoteService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/Domain/GitRemoteService.swift)
- [XcodeBuildService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Xcode/XcodeBuildService.swift)
- [ProcessExecutor.swift](/Users/uyakauleu/development/aizen/aizen/Utilities/ProcessExecutor.swift)
- [GitDiffRuntimeStore.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/GitDiffRuntimeStore.swift)
- [GitSummaryStore.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/GitSummaryStore.swift)

Those may still need local cleanup, but their fundamental boundary choice is sound.

## Real Boundary Smells

### 1. Actor used as both store and sync query facade

This is the clearest smell in the codebase.

Representative file:

- [AgentRegistry.swift](/Users/uyakauleu/development/aizen/aizen/Services/Agent/AgentRegistry.swift)

Symptoms:

- actor owns mutable registry state
- actor also exposes many synchronous `nonisolated` query helpers
- actor also owns persistence details
- actor also maintains a second lock-backed cache for sync access

That is a boundary failure, not just a `nonisolated` problem.

### 2. Actor used as both runtime and pure helper namespace

Representative files:

- [TmuxSessionManager.swift](/Users/uyakauleu/development/aizen/aizen/Services/Terminal/TmuxSessionManager.swift)
- [GitHostingService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/GitHostingService.swift)

Symptoms:

- actor owns stateful runtime behavior
- same actor also owns executable lookup, URL building, provider parsing, or command assembly
- `nonisolated` exists because the pure logic does not belong on the actor at all

### 3. `@MainActor` type used as an operation launcher instead of a UI state owner

Representative file:

- [GitOperationService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/GitOperationService.swift)

Symptoms:

- `@MainActor` observable object owns little actual state beyond pending status
- almost every mutation method immediately captures values and launches `Task.detached`
- background services do the real work
- the main-actor type is effectively a UI wrapper around an operation runner

This is not as bad as `AgentRegistry`, but it signals the wrong ownership shape.

The likely better shape is:

- a plain operation runner or actor for mutations
- a tiny `@MainActor` observable coordinator only if UI needs published state

### 4. `@MainActor` session object owning non-UI I/O entry points

Representative file:

- [AgentSession.swift](/Users/uyakauleu/development/aizen/aizen/Services/Agent/AgentSession.swift)

Symptoms:

- session object is clearly UI/session state
- file read/write request handling is kept on the same type
- `nonisolated` exists to escape main-actor isolation for file I/O

This is a smaller smell, but still a sign that the operational boundary should be extracted.

### 5. View/runtime managers that are not marked `@MainActor` but behave like UI stores

Representative file:

- [XcodeBuildManager.swift](/Users/uyakauleu/development/aizen/aizen/Managers/XcodeBuildManager.swift)

Symptoms:

- `ObservableObject` with many published properties
- lots of manual `MainActor.run` hopping
- effectively a UI-facing state owner

This is not a correctness failure by itself, but it is a maintainability smell. A UI-facing observable manager should generally be explicitly `@MainActor` unless there is a strong reason not to be.

### 6. `@MainActor` view models that still own repository or filesystem runtime work

Representative file:

- [FileBrowserViewModel.swift](/Users/uyakauleu/development/aizen/aizen/Views/Files/FileBrowserViewModel.swift)

Symptoms:

- UI-facing view model owns open file state, tree expansion state, and Core Data session state
- the same type also owns git status scanning and git-ignored checks
- it uses detached tasks to run libgit2 scans and filesystem enumeration from inside the view model

This is the same boundary smell in a different form:

- the view model is both the UI state owner and the filesystem/git runtime

That is manageable at small scale, but it is not the right long-term shape for a worktree-sized surface.

## Core Design Rules

### Rule 1

Use `actor` only when the type must serialize mutable shared state or side effects.

Good reasons:

- caches with mutation
- process lifecycle ownership
- CLI/auth/runtime probing
- filesystem watcher multiplexing
- network or subprocess state that should not race

Bad reasons:

- wanting a namespace for helpers
- wanting to “be safe” around pure logic
- mixing async work into a type that mostly serves sync queries

### Rule 2

Use `@MainActor` only for UI-owned state and coordination.

Good reasons:

- `ObservableObject` or observable state directly bound to SwiftUI
- user-triggered action coordination that updates published UI state
- window/session managers with direct UI lifecycle responsibilities

Bad reasons:

- wrapping a background operation layer and immediately detaching everything
- keeping file/network/process work on a UI type just because the type is convenient

### Rule 3

Pure logic must not live on isolated runtime types.

Move these out first:

- URL builders
- git hosting parsers
- tmux command builders
- persistence encoders/decoders
- immutable query helpers over snapshots

### Rule 4

Prefer snapshots over sync actor escape hatches.

If code needs fast synchronous reads, do not poke holes through an actor. Instead:

- refresh an immutable snapshot after mutation
- expose sync queries on that snapshot or on a plain helper over that snapshot

### Rule 5

`Task.detached` should be rare and justified.

Use it when you truly want:

- independence from current actor
- no inheritance of cancellation or actor context
- a separate priority/ownership boundary

Do not use it as the default way to “get off the main actor” from a UI type. In many cases:

- a dedicated actor
- a nonisolated helper
- or a normal `Task` from the correct owner

is the cleaner model.

### Rule 6

Do not let a SwiftUI-facing view model become the runtime owner for repository scans, filesystem enumeration, or similar worktree services.

If a view model starts accumulating:

- detached work for git scans
- detached work for directory crawling
- persistence writes
- UI tree state

it should usually be split into:

- a `@MainActor` state store for UI data
- one or more runtime helpers or actors for the expensive work

## Priority Refactors

### Phase 1: `AgentRegistry` boundary split

Primary file:

- [AgentRegistry.swift](/Users/uyakauleu/development/aizen/aizen/Services/Agent/AgentRegistry.swift)

New shape:

- `AgentRegistryStore` actor
- `AgentCatalogStore` `@MainActor` observable store
- `AgentRegistrySnapshot` value type
- `AgentRegistryQueries` plain helper
- `AgentRegistryPersistence` plain helper
- `AgentLaunchResolver` plain helper or dedicated async service
- `AgentAuthPreferences` plain persistence helper
- `AgentValidator` async validation service

Outcomes:

- remove `nonisolated(unsafe)`
- remove lock-backed shadow cache
- remove sync `nonisolated` actor facade
- remove direct view-driven `NotificationCenter` reload patterns for agent metadata
- move SwiftUI consumers to a main-actor catalog snapshot instead of ad hoc global reads

This remains the highest-priority concurrency cleanup in the repo.

### Phase 2: `TmuxSessionManager` runtime split

Primary file:

- [TmuxSessionManager.swift](/Users/uyakauleu/development/aizen/aizen/Services/Terminal/TmuxSessionManager.swift)

New shape:

- `TmuxRuntime` actor
- `TmuxEnvironment` plain helper
- `TmuxCommandBuilder` plain helper

Outcomes:

- actor only owns real tmux session mutation/lifecycle
- no `nonisolated` helper namespace behavior on the actor

### Phase 3: `GitHostingService` runtime split

Primary file:

- [GitHostingService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/GitHostingService.swift)

New shape:

- `GitHostingRuntime` actor
- `GitHostingParser` plain helper
- `GitHostingURLBuilder` plain helper

Outcomes:

- actor owns only runtime cache/auth/command concerns
- parser and browser-link logic become fully plain and synchronous

### Phase 4: `GitOperationService` ownership cleanup

Primary file:

- [GitOperationService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/GitOperationService.swift)

New shape:

Option A:

- `GitOperationRunner` actor or plain async service for mutations
- `GitOperationStore` `@MainActor` observable coordinator only for pending/error state

Option B:

- make `GitOperationService` itself a non-`@MainActor` operation owner
- publish UI state back through a smaller `@MainActor` adapter

Preferred direction:

- separate mutation execution from UI observability

Outcomes:

- fewer detached tasks launched from a UI-owned service
- clearer cancellation and ownership model
- easier testing for mutation workflows

### Phase 5: `AgentSession` I/O extraction

Primary file:

- [AgentSession.swift](/Users/uyakauleu/development/aizen/aizen/Services/Agent/AgentSession.swift)

New shape:

- `AgentSessionIOBridge` plain helper or dedicated actor
- `AgentSession` remains focused on session lifecycle and published UI state

Outcomes:

- remove file I/O escape hatches from session state object
- make ACP file operation handling explicit

### Phase 6: `XcodeBuildManager` explicit UI isolation

Primary file:

- [XcodeBuildManager.swift](/Users/uyakauleu/development/aizen/aizen/Managers/XcodeBuildManager.swift)

New shape:

- mark manager explicitly `@MainActor`
- keep project detection, device listing, and build execution in dedicated async services/actors

Outcomes:

- fewer manual `MainActor.run` hops
- clearer UI/runtime split
- more obvious rules for future edits

### Phase 7: `FileBrowserViewModel` runtime split

Primary file:

- [FileBrowserViewModel.swift](/Users/uyakauleu/development/aizen/aizen/Views/Files/FileBrowserViewModel.swift)

New shape:

- `FileBrowserStateStore` `@MainActor`
- `FileTreeLoader` plain async helper or actor
- `FileBrowserGitStatusRuntime` plain async helper or actor
- existing persistence/session writes kept behind a narrower persistence helper if needed

Outcomes:

- the view model stops owning git status scans directly
- directory enumeration and git ignore/status work move out of the UI store
- file browser UI becomes easier to reason about and test

This is lower priority than `AgentRegistry` and `GitOperationService`, but it is the next clear concurrency-boundary candidate found in the broader audit.

## Migration Strategy

### Step 1

Implement [nonisolated-boundary-refactor-spec.md](/Users/uyakauleu/development/aizen/docs/specs/nonisolated-boundary-refactor-spec.md) Phases 1 through 3 first:

- `AgentRegistry`
- `TmuxSessionManager`
- `GitHostingService`

Those are the highest-signal fixes and remove the worst isolation boundary errors.

### Step 2

Refactor `GitOperationService` next.

This is the first broader cleanup beyond `nonisolated`, because it addresses a main-actor ownership issue rather than a direct escape hatch count.

### Step 3

Extract file I/O from `AgentSession`.

This is architecturally worthwhile, but less urgent than the registry and git operation boundaries.

### Step 4

Normalize UI-facing managers like `XcodeBuildManager` to explicit `@MainActor` where appropriate.

Do not combine this with heavy behavioral changes unless profiling shows a real issue.

### Step 5

Refactor `FileBrowserViewModel` after the higher-priority registry/git boundaries.

This should be treated as a UI/runtime split, not as a generic file-browser rewrite.

## Verification

For each phase:

- build the app
- search the touched subsystem for `nonisolated`, `Task.detached`, and missing `@MainActor` boundaries
- confirm pure logic moved out of isolated types instead of being wrapped in new shims

Suggested checks:

- `rg -n "\\bnonisolated\\b|Task\\.detached|@MainActor|\\bactor\\b" aizen/Services/Agent`
- `rg -n "\\bnonisolated\\b|Task\\.detached|@MainActor|\\bactor\\b" aizen/Services/Git`
- `rg -n "\\bnonisolated\\b|Task\\.detached|@MainActor|\\bactor\\b" aizen/Services/Terminal`
- `rg -n "\\bnonisolated\\b|Task\\.detached|@MainActor|\\bactor\\b" aizen/Managers/XcodeBuildManager.swift`
- `xcodebuild -project /Users/uyakauleu/development/aizen/aizen.xcodeproj -scheme aizen -configuration Debug -sdk macosx build`

## Success Criteria

- isolated types no longer double as pure helper namespaces
- sync reads no longer depend on actor escape hatches in the high-priority subsystems
- UI-facing services own UI state, not heavyweight runtime work
- `Task.detached` usage becomes narrow and intentional instead of structural glue
- remaining actor and `@MainActor` boundaries are easy to explain in terms of ownership

## Additional Audit Notes

The broader scan found some files with concurrency markers that do not currently justify spec-level refactors.

### Acceptable for now

- [MLXModelManager.swift](/Users/uyakauleu/development/aizen/aizen/Services/Audio/MLXModelManager.swift)
  - `@MainActor` UI-facing manager
  - detached work is limited to storage/repo-size calculations
  - this looks like local cleanup territory, not a major ownership failure

- [MCPManager.swift](/Users/uyakauleu/development/aizen/aizen/Services/MCP/MCPManager.swift)
  - `@MainActor` observable coordinator
  - delegates real persistence/mutation to actor-backed server store
  - boundary is broadly correct

- [TerminalSplitController.swift](/Users/uyakauleu/development/aizen/aizen/Views/Terminal/Components/TerminalSplitController.swift)
  - `@MainActor` controller for UI/session state
  - no comparable isolation escape-hatch pattern was found here

### Related but already covered elsewhere

- [WorkflowService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Workflow/WorkflowService.swift)
  - still a valid lifecycle/refresh target
  - already addressed in the worktree/git/xcode runtime refactor direction

## Expected Outcome

After this refactor, Aizen should have a simpler concurrency story:

- domain actors for serialized runtime state
- main-actor stores for UI state
- plain helpers for pure logic
- explicit snapshots for sync reads

That is a better long-term foundation than continuing to patch isolation issues one `nonisolated` or detached task at a time.

## Agent Registry Notes

`AgentRegistry` needs a more explicit target architecture than the rest of the spec because it currently mixes more concerns than a normal isolated type.

Today it acts as all of these at once:

- mutable metadata store
- persistence layer
- sync query API for the whole app
- auth preference storage
- launch path/args/environment resolver
- validation entry point
- global invalidation broadcaster via `NotificationCenter`

That should be split deliberately.

### Target shape

#### `AgentRegistryStore` actor

Owns:

- mutation of stored agent metadata
- persistence writes for catalog data
- initial catalog bootstrap

Does not own:

- synchronous app-wide reads
- auth preference APIs
- shell environment loading
- executable validation
- SwiftUI invalidation fan-out

#### `AgentCatalogStore` `@MainActor`

Owns:

- current immutable `AgentRegistrySnapshot`
- SwiftUI-observable arrays and lookup surfaces
- refresh after registry mutations

This is the app-facing read model.

Views and view models should stop calling global synchronous registry methods directly. They should read from this catalog store instead.

Representative migration targets:

- [SettingsView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/SettingsView.swift)
- [WorktreeSessionTabs.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/WorktreeSessionTabs.swift)
- [AgentSelectorMenu.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/AgentSelectorMenu.swift)
- [ModelSelectorMenu.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/ModelSelectorMenu.swift)

#### `AgentLaunchResolver`

Owns:

- executable path resolution
- launch args resolution
- launch environment resolution
- shell environment merge

This boundary is separate because launch resolution is operational and partially async. It should not be bundled into the catalog store.

#### `AgentAuthPreferences`

Owns:

- save/get/clear auth preference
- skip-auth preference handling

This is simple preferences state, not catalog state.

#### `AgentValidator`

Owns:

- command-based validation such as `which`
- executable path validation
- optional cached validation status if needed for settings UI

Important:

- validation must not remain a synchronous UI-facing operation hanging off the registry
- the current behavior in [AgentDiscoveryService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Agent/AgentDiscoveryService.swift) blocks on `Process.waitUntilExit()`
- the target design should move validation to async service boundaries and cache state where the UI benefits from it

### Notification migration

The current metadata update model relies on `agentMetadataDidChange` and manual reloads in views.

Representative current consumers:

- [SettingsView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/SettingsView.swift)
- [WorktreeSessionTabs.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/WorktreeSessionTabs.swift)
- [ChatTabView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/ChatTabView.swift)

That should be treated as part of the refactor, not as an unrelated cleanup.

Target rule:

- mutation happens through the store actor
- the main-actor catalog refreshes its snapshot
- SwiftUI observes catalog state directly
- `NotificationCenter` should not remain the primary invalidation mechanism for agent metadata
