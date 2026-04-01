# Git, Diff, Workflow, and Xcode Runtime Refresh Refactor

## Summary

Refactor worktree runtime refresh behavior so Aizen performs Git, diff, workflow, and Xcode state work only for the worktree and surface the user is actively using.

The current implementation is functionally correct but too view-driven. Several surfaces independently own refresh policy, create service instances, subscribe to the same watcher, and trigger expensive status or diff recomputation. That creates avoidable invalidation, duplicate libgit2 work, repeated CLI calls, and unnecessary SwiftUI layout churn.

This refactor introduces:

- one shared worktree-scoped runtime owner
- one shared Git summary store per worktree
- one shared diff runtime per worktree
- visibility-scoped activation for workflow and Xcode
- explicit cache, staleness, and eviction rules
- separation of mutation services from observable runtime state

## Problem Statement

The same worktree is currently observed and refreshed from multiple independent surfaces:

- [WorktreeDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeDetailView.swift)
- [GitPanelWindowContent.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/GitPanelWindowContent.swift)
- [CompanionGitDiffView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/CompanionGitDiffView.swift)

Those surfaces either own or trigger:

- Git status reloads
- watcher subscriptions
- diff recomputation
- workflow refresh and log polling
- Xcode project detection and destination refresh

The watcher layer is deduped per worktree path, but the refresh fan-out is not. A single file system event still causes multiple subscribers to independently call status reloads or diff updates.

The result is not one pathological hot loop. It is cumulative duplicated work:

- duplicated `reloadStatus(lightweight:)` requests
- summary state being republished even when semantically unchanged
- diff recomputation from multiple UI paths
- workflow timers owned by tab lifecycle
- Xcode detection owned by view lifecycle with global rather than worktree-scoped cache keys

## Evidence From Current Code

### 1. Git refresh ownership is duplicated

- [WorktreeDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeDetailView.swift#L660) runs `setupGitMonitoring()` from `.task(id: worktree.id)`.
- [WorktreeDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeDetailView.swift#L731) subscribes directly to [GitIndexWatchCenter.swift](/Users/uyakauleu/development/aizen/aizen/Utilities/GitIndexWatchCenter.swift) and calls `reloadStatus(lightweight: true)`.
- [GitPanelWindowContent.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/GitPanelWindowContent.swift#L251) calls `reloadStatus()` on appear and also calls `setupGitWatcher()`.
- [CompanionGitDiffView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/CompanionGitDiffView.swift#L84) calls `reloadStatus()` on appear and [CompanionGitDiffView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/CompanionGitDiffView.swift#L141) adds another watcher subscription.

### 2. Watcher dedupe does not prevent reload duplication

[GitIndexWatchCenter.swift](/Users/uyakauleu/development/aizen/aizen/Utilities/GitIndexWatchCenter.swift#L23) dedupes the underlying watcher per worktree path, but it stores arbitrary callbacks and fans a watcher event out to every subscriber in [GitIndexWatchCenter.swift](/Users/uyakauleu/development/aizen/aizen/Utilities/GitIndexWatchCenter.swift#L94).

That means one `.git/index` or `HEAD` change can still trigger multiple independent reload paths.

### 3. "Lightweight" Git status is still non-trivial

[GitRepositoryService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/GitRepositoryService.swift#L400) always maps a `DetailedGitStatus` into full observable `GitStatus`.

[GitStatusService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/Domain/GitStatusService.swift#L24) still does all of the following even when `includeDiffStats` is false:

- open repository
- call `repo.status(...)`
- read current branch
- compute ahead/behind

That is acceptable for one active surface, but not when multiple surfaces independently trigger it.

### 4. Git state is republished without semantic dedupe

[GitRepositoryService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/GitRepositoryService.swift#L421) assigns `currentStatus` and `repositoryState` on every successful reload. There is no semantic equality gate before publication.

That means repeated watcher activity can invalidate SwiftUI even if the visible summary state did not actually change.

### 5. Diff work is a separate hot path and must be treated as one

[CompanionGitDiffView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/CompanionGitDiffView.swift#L104) reacts to every `gitStatus` change by reloading diff.

[CompanionGitDiffView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/CompanionGitDiffView.swift#L196) computes:

- `diffUnified()`
- `diffStagedUnified()`
- `diffUnstagedUnified()`
- fallback `status()` for untracked files
- reads untracked file contents to synthesize diff output

So centralizing status alone is not enough. Shared diff ownership is part of Phase 1, not a later optimization.

### 6. Workflow refresh is still too eager

[GitPanelWindowContent.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/GitPanelWindowContent.swift#L430) configures the workflow service on first appearance, and on later appearances enables auto-refresh and immediately calls `refresh()`.

[WorkflowService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Workflow/WorkflowService.swift#L50) configures provider state and immediately:

- loads workflows
- loads runs
- starts a 60 second refresh loop

[WorkflowService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Workflow/WorkflowService.swift#L498) also starts a 5 second polling loop for active run logs.

This is only acceptable while the workflow surface is actively visible.

### 7. Xcode state is cached incorrectly and owned by a view

[WorktreeDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeDetailView.swift#L666) always calls `xcodeBuildManager.detectProject(at:)` from the worktree task.

[XcodeBuildManager.swift](/Users/uyakauleu/development/aizen/aizen/Managers/XcodeBuildManager.swift#L66) makes detection lifecycle view-owned.

[XcodeBuildManager.swift](/Users/uyakauleu/development/aizen/aizen/Managers/XcodeBuildManager.swift#L43) stores one global `xcodeLastDestinationId`, and [XcodeBuildManager.swift](/Users/uyakauleu/development/aizen/aizen/Managers/XcodeBuildManager.swift#L153) stores one global destinations cache. That is not worktree-safe.

## Goals

- A worktree should have one canonical Git summary store.
- A worktree should have one canonical diff runtime.
- UI surfaces should subscribe to cached runtime state, not own refresh policy.
- Hidden worktrees should not perform active Git, diff, workflow, or Xcode refresh.
- Git publication should avoid emitting semantically identical summary state.
- Diff recomputation should happen only when a diff consumer is visible.
- Workflow refresh should run only while workflow UI is visible.
- Xcode project and destination state should be cached per worktree or per project, not globally.
- Reopening a surface should reuse fresh cached state instead of cold-starting runtime work.

## Non-Goals

- Replacing libgit2 with shell Git.
- Redesigning the Git panel UI.
- Rewriting workflow provider implementations.
- Changing how builds are executed once an Xcode build is actually started.

## Production Principles

This refactor should follow the same broad shape used by mature IDEs and desktop source-control tools:

- one runtime owner per resource scope
- cached snapshots for read-mostly UI
- visibility-driven activation
- explicit invalidation after mutations
- background work separated from SwiftUI view lifetime

This direction is consistent with Apple guidance on narrowing observable dependencies and minimizing unnecessary SwiftUI invalidation, and with Git performance guidance that repeated worktree scans should be reduced where possible.

## Proposed Architecture

### 1. Introduce `WorktreeRuntimeCoordinator`

Suggested location:

- `aizen/Services/Worktree/WorktreeRuntimeCoordinator.swift`

Responsibilities:

- own one `GitSummaryStore` per worktree path
- own one `GitDiffRuntimeStore` per worktree path
- own one `WorkflowRuntimeStore` per worktree path
- own one `XcodeProjectRuntimeStore` per worktree path
- track which surfaces are attached and visible
- compute which subsystems should be active
- be the only component that subscribes to `GitIndexWatchCenter`

Tracked visibility should include:

- detail view attached
- Git panel visible
- Git panel active tab
- companion diff visible
- workflow surface visible
- Xcode surface visible

Views stop owning refresh policy. Views report visibility and consume snapshots.

### 2. Split mutation from observable state

Current problem:

- [GitRepositoryService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/GitRepositoryService.swift) mixes mutation commands with published state.

Refactor into:

- `GitOperationService`
  - stage, unstage, commit, fetch, pull, push, checkout
  - no long-lived published UI state
- `GitSummaryStore`
  - observable summary snapshot only
  - owned by worktree runtime coordinator
- `GitDiffRuntimeStore`
  - observable diff state and diff loading only
  - owned by worktree runtime coordinator

This split is not optional. It is required for reliable dedupe, throttling, and testability.

### 3. Simplify refresh tiers for the first implementation

The previous draft proposed too many tiers too early.

Phase 1 should start with just two:

- `summary`
  - repository state
  - staged files
  - modified files
  - untracked files as needed for visible summary consumers
  - conflicted files
  - current branch
  - ahead/behind
  - no diff stats
- `full`
  - everything required by the Git panel and diff consumers

Only add finer-grained tiers later if profiling shows clear value.

### 4. Centralize watcher delivery

[GitIndexWatchCenter.swift](/Users/uyakauleu/development/aizen/aizen/Utilities/GitIndexWatchCenter.swift) should remain a low-level watcher substrate, but it should no longer fan out arbitrary callbacks from views or ad hoc services.

New rule:

- `GitIndexWatchCenter` delivers worktree change notifications only to `WorktreeRuntimeCoordinator`

The coordinator then decides whether to:

- ignore the event
- mark stores stale
- enqueue a coalesced summary refresh
- enqueue a coalesced full refresh
- enqueue diff refresh only if a diff consumer is visible

### 5. Add explicit staleness, cache age, and eviction rules

The previous draft did not define runtime lifetime clearly enough.

For each worktree runtime:

- create on first surface attach
- retain while any surface is attached
- when last surface detaches:
  - stop active refresh and polling immediately
  - keep warm cache for a short idle TTL
  - evict runtime after inactivity

Required metadata:

- `isStale`
- `lastSummaryRefreshAt`
- `lastFullRefreshAt`
- `lastDiffRefreshAt`
- `lastWorkflowRefreshAt`
- `lastXcodeRefreshAt`
- `attachedSurfaceCount`

Initial policy:

- hidden worktree:
  - mark stale only
  - no immediate status or diff refresh
- visible summary-only worktree:
  - coalesced summary refresh
- visible diff consumer:
  - coalesced diff refresh
- visible workflow tab:
  - workflow refresh active
- visible Xcode surface:
  - Xcode runtime active

Initial TTL guidance:

- Git summary: 2 to 5 seconds
- Git diff: 5 to 10 seconds unless explicitly invalidated
- Workflow runs list: 60 seconds while visible
- Xcode destinations: several minutes unless explicitly refreshed
- Worktree runtime warm-cache eviction: short idle TTL, for example 30 to 120 seconds

### 6. Publish only meaningful Git summary changes

`GitSummaryStore` should compare the new summary snapshot to the previous one before publishing.

Use separate snapshot types:

- `GitSummarySnapshot`
- `GitDiffSnapshot`

Toolbar badges and compact summary consumers should observe only `GitSummarySnapshot`.

This prevents:

- summary-only UI invalidation from full diff refresh
- repeated layout work when watcher events do not change visible summary state

### 7. Treat diff as a visibility-scoped runtime, not a view helper

This is a required change, not a later polish item.

`GitDiffRuntimeStore` should:

- own current diff output
- know whether a diff consumer is visible
- refresh only when a diff consumer is visible and data is stale
- cancel in-flight diff loads when hidden
- dedupe repeat requests for the same worktree and revision state

The first migration targets:

- [CompanionGitDiffView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/CompanionGitDiffView.swift)
- Git panel diff side in [GitPanelWindowContent.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/GitPanelWindowContent.swift)

### 8. Scope workflow strictly to workflow visibility

Keep one `WorkflowRuntimeStore` per worktree path.

Lifecycle rules:

- lazily configure on first workflow-tab entry
- stop 60 second refresh timer as soon as workflow tab is hidden
- stop 5 second log polling as soon as the selected run UI is hidden
- reuse fresh cached workflows and runs on reopen
- do not call immediate `refresh()` on every appearance if cached state is still fresh

### 9. Fix Xcode caching and activation

`XcodeBuildManager` behavior should be split into:

- `XcodeProjectRuntimeStore`
  - detected project
  - schemes
  - destinations
  - readiness
- `XcodeBuildOperationService`
  - build/run actions

Required Xcode cache corrections:

- destination cache key must be scoped per worktree or project path
- last selected destination must be scoped per worktree or project path
- project detection should not run for hidden worktrees

Initial activation policy:

- activate when worktree detail view is active and Xcode UI is enabled
- reuse cached project detection and destinations
- refresh destinations only on stale cache or explicit user request

## Rollout Plan

### Phase 1: Git summary and diff consolidation

This is the first implementation phase and should stand alone.

Deliverables:

- introduce `WorktreeRuntimeCoordinator`
- introduce `GitSummaryStore`
- introduce `GitDiffRuntimeStore`
- keep `GitIndexWatchCenter` as watcher substrate but make coordinator its only consumer
- remove per-surface watcher ownership from:
  - [WorktreeDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/WorktreeDetailView.swift)
  - [GitPanelWindowContent.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/GitPanelWindowContent.swift)
  - [CompanionGitDiffView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Chat/Components/CompanionGitDiffView.swift)
- keep `GitOperationService` as the mutation layer
- add semantic equality guard for summary publication

Success criteria:

- one watcher notification produces at most one summary refresh request per worktree
- diff work only runs while a diff consumer is visible
- Git panel and companion diff no longer own their own Git watcher subscriptions

### Phase 2: Workflow runtime isolation

Deliverables:

- move workflow lifecycle ownership out of `GitPanelWindowContent`
- cache workflow list and run list per worktree
- make timer and log polling visibility-scoped

Success criteria:

- closing workflow UI stops all workflow timers
- reopening workflow UI reuses recent cached state when valid

### Phase 3: Xcode runtime cache correction

Deliverables:

- split Xcode runtime state from Xcode build operations
- make cache keys project-scoped or worktree-scoped
- stop eager detection for hidden worktrees

Success criteria:

- switching worktrees does not thrash global Xcode cache state
- Xcode data does not refresh just because a view instance was recreated

## Migration Notes

- Do not attempt to refactor Git, workflow, and Xcode in a single giant patch.
- Keep the first pass narrow enough to verify behavior with profiling and real usage.
- Prefer compatibility adapters where needed so the UI can migrate incrementally.
- Existing user-facing behavior should remain the same unless the change is directly about refresh policy.

## Validation Plan

Measure before and after:

- watcher-triggered reload count per worktree
- Git summary reload count per minute during normal terminal usage
- diff recomputation count while companion diff is hidden
- workflow timer count while workflow UI is hidden
- Xcode detection count across tab and worktree switches

Manual test flows:

1. Open one worktree, use terminal heavily, keep Git panel closed.
2. Open Git panel, switch tabs, close Git panel, continue working.
3. Open companion diff, stream agent output, then stop.
4. Switch between multiple worktrees repeatedly.
5. Toggle workflow tab open and closed.
6. Toggle Xcode UI visibility and switch worktrees.

Expected outcomes:

- no progressive slowdown after opening and closing Git panel
- lower main-thread SwiftUI invalidation from Git state churn
- no duplicated watcher-triggered reload fan-out
- no hidden-surface diff recomputation
- no hidden workflow polling
- stable Xcode state across view recreation
