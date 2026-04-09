# Persistence and State Boundary Refactor

## Summary

Aizen does not mainly have a "Core Data is too slow" problem.

It has a persistence-boundary problem:

- Core Data entities are used directly as UI models
- feature views recompute derived state by traversing managed-object relationships
- background saves merge into the main context and invalidate view trees that do not own that change
- several mutation paths perform multiple small saves for one logical action
- manual `objectWillChange`, delayed notifications, and ad hoc fetches are compensating for unclear ownership

This spec defines the architecture needed to make state updates stable:

- Core Data is the durable store, not the runtime UI model
- feature `Application` stores own observable UI state
- `Infrastructure` owns query controllers and write services
- views consume snapshot values and selected IDs, not `NSManagedObject` graphs
- each logical mutation commits through one write boundary

This is not a generic persistence cleanup.

It is a boundary correction aligned with the feature-first migration direction in:

- [feature-first-architecture-migration-spec.md](/Users/uyakauleu/development/aizen/docs/specs/feature-first-architecture-migration-spec.md)

## Project Context

Aizen already shows the right architectural direction:

- feature-first structure under `Features/`
- `Application` for state and orchestration
- `Infrastructure` for Core Data, filesystem, ACP, libgit2, and platform integrations
- `UI` for presentation

The remaining instability comes from older patterns that are still active inside the new structure:

- `NSManagedObject` types are passed directly into views and stores
- view helpers fetch from `viewContext`
- relationship traversal is used as a live query mechanism
- persistence writes are issued from UI-facing stores
- runtime coordination still falls back to `NotificationCenter` timing

Those patterns are manageable at small scale, but they do not compose once:

- chat messages stream rapidly
- multiple worktree surfaces stay open
- background contexts merge frequently
- Core Data relationship graphs get larger

## Problem Statement

The current implementation mixes four different responsibilities into the same live object graph:

1. durable storage
2. runtime session state
3. UI-facing observable state
4. read-model/query composition

That causes two classes of failures:

- correctness instability
  - stale reads
  - timing-sensitive navigation
  - extra invalidation to "force" UI updates
  - background merges reaching views that should not care

- performance instability
  - repeated fetches during view recomputation
  - repeated whole-graph traversal for counts, labels, and selection
  - write amplification from small repeated saves
  - broad SwiftUI invalidation for narrow state changes

The code is often functionally correct. The issue is that correctness currently depends on incidental ordering and eager invalidation rather than explicit ownership.

## Evidence From Current Code

### 1. Chat streaming still invalidates the whole timeline

- [ChatAgentSession+StreamingFinalization.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/Infrastructure/ACP/ChatAgentSession+StreamingFinalization.swift#L98) flushes every chunk immediately because `agentMessageFlushInterval` is `0`.
- [ChatAgentSession+StreamingFinalization.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/Infrastructure/ACP/ChatAgentSession+StreamingFinalization.swift#L82) replaces the full `messages` array on each flush.
- [ChatSessionStore+SessionObservers.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/Application/ChatSessionStore+SessionObservers.swift#L32) observes `session.$messages`.
- [ChatSessionStore+Timeline.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/Application/ChatSessionStore+Timeline.swift#L32) bumps `timelineRenderEpoch` for each message sync.
- [ChatTimelineContainer.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/UI/ChatTimelineContainer.swift#L27) treats the epoch key as the `Equatable` identity gate.

This is not a row update model. It is a full timeline invalidation model.

### 2. One logical chat mutation performs multiple persistence saves

- [ChatAgentSession+MessageMutation.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/Infrastructure/ACP/ChatAgentSession+MessageMutation.swift#L23) starts persistence from the session runtime.
- [ChatAgentSession+MessageMutation.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/Infrastructure/ACP/ChatAgentSession+MessageMutation.swift#L26) first updates `messageCount` and `lastMessageAt`.
- [ChatAgentSessionMessaging+Persistence.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/Infrastructure/ACP/ChatAgentSessionMessaging+Persistence.swift#L12) creates one background context just for metadata.
- [ChatAgentSessionMessaging+Persistence.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/Infrastructure/ACP/ChatAgentSessionMessaging+Persistence.swift#L31) then creates another background context for the `ChatMessage` insert.
- [PersistenceController.swift](/Users/uyakauleu/development/aizen/aizen/Shared/Persistence/PersistenceController.swift#L77) enables automatic main-context merge from parent/background saves.

This creates extra merge waves for a single user send.

### 3. Views perform Core Data fetches while deriving presentation state

- [PermissionBannerView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/UI/Components/PermissionBannerView.swift#L20) derives banner state in a computed property.
- [PermissionBannerView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/UI/Components/PermissionBannerView.swift#L35) creates a fetch request inside that view helper.
- [PermissionBannerView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/UI/Components/PermissionBannerView.swift#L40) fetches from `viewContext` to get the worktree name.

- [ActiveTabIndicatorView+Support.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/Components/ActiveTabIndicatorView+Support.swift#L11) derives active tab info in a computed property.
- [ActiveTabIndicatorView+Support.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/Components/ActiveTabIndicatorView+Support.swift#L49) fetches `ChatSession`.
- [ActiveTabIndicatorView+Support.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/Components/ActiveTabIndicatorView+Support.swift#L56) fetches `TerminalSession`.
- [ActiveTabIndicatorView+Support.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/Components/ActiveTabIndicatorView+Support.swift#L63) fetches `BrowserSession`.

These are read-model queries living in view code.

### 4. File browser session persistence is too eager

- [FileBrowserStore.swift](/Users/uyakauleu/development/aizen/aizen/Features/Files/Application/FileBrowserStore.swift#L99) persists on every expand/collapse.
- [FileBrowserStore+EditorState.swift](/Users/uyakauleu/development/aizen/aizen/Features/Files/Application/FileBrowserStore+EditorState.swift#L14) persists when browsing into a directory.
- [FileBrowserStore+EditorState.swift](/Users/uyakauleu/development/aizen/aizen/Features/Files/Application/FileBrowserStore+EditorState.swift#L44) persists after every opened file.
- [FileBrowserStore+SessionPersistence.swift](/Users/uyakauleu/development/aizen/aizen/Features/Files/Application/FileBrowserStore+SessionPersistence.swift#L32) restores open files by looping and calling `openFile`.
- [FileBrowserStore+SessionPersistence.swift](/Users/uyakauleu/development/aizen/aizen/Features/Files/Application/FileBrowserStore+SessionPersistence.swift#L57) serializes the full session payload and saves synchronously on the main context each time.

This is persistence coupled directly to UI interaction frequency.

### 5. Manual invalidation is compensating for unclear state ownership

- [AgentSwitcher.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/Application/AgentSwitcher.swift#L29) manually calls `session.objectWillChange.send()`.
- [AgentSwitcher.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/Application/AgentSwitcher.swift#L30) manually calls `worktree.objectWillChange.send()`.
- [WorkspaceRepositoryStore+Repositories.swift](/Users/uyakauleu/development/aizen/aizen/Features/Workspace/Application/WorkspaceRepositoryStore+Repositories.swift#L95) manually calls `workspace?.objectWillChange.send()`.
- [WorktreeTabStateStore.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/Application/WorktreeTabStateStore.swift#L73) and [WorktreeTabStateStore.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/Application/WorktreeTabStateStore.swift#L94) manually emit `objectWillChange` after mutating `@Published` state.

Those calls are not the root problem. They are evidence that the actual read model is not explicit enough.

### 6. Relationship traversal is being used as a live query engine

- [WorktreeSessionCoordinator.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/Application/WorktreeSessionCoordinator.swift#L22) derives chat sessions by traversing `worktree.chatSessions`.
- [WorktreeSessionCoordinator.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/Application/WorktreeSessionCoordinator.swift#L36) does the same for terminal sessions.
- [RepositoryRow+Label.swift](/Users/uyakauleu/development/aizen/aizen/Features/Workspace/UI/Components/RepositoryRow+Label.swift#L4) computes repository session count by traversing repository -> worktrees -> session sets.
- [WorktreeListItemView+Data.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/Components/WorktreeListItemView+Data.swift#L47) computes session counts by traversing to-many relationships in row-view helpers.

This makes view cost proportional to relationship graph shape rather than to an explicit snapshot.

### 7. Managed objects still cross directly into UI boundaries

- [ChatSessionView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Chat/UI/ChatSessionView.swift#L15) observes `ChatSession` directly.
- [WorktreeDetailView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/WorktreeDetailView.swift#L14) observes `Worktree` directly.

This means durable-store change propagation and UI state propagation are still partially the same mechanism.

### 8. Navigation still relies on fetches plus delayed notifications

- [AppWorktreeNavigator.swift](/Users/uyakauleu/development/aizen/aizen/App/Navigation/AppWorktreeNavigator.swift#L45) fetches the target `ChatSession` from Core Data during navigation.
- [AppWorktreeNavigator.swift](/Users/uyakauleu/development/aizen/aizen/App/Navigation/AppWorktreeNavigator.swift#L61) posts a delayed notification to complete selection.
- [AppWorktreeNavigator.swift](/Users/uyakauleu/development/aizen/aizen/App/Navigation/AppWorktreeNavigator.swift#L121) posts primary and retry notifications with timing offsets.

That is coordination by timing rather than by explicit navigation state.

## Goals

- Make persistence updates stable under background merges and high-frequency runtime updates.
- Reduce SwiftUI invalidation fan-out caused by Core Data graph changes.
- Ensure one logical mutation maps to one persistence transaction whenever practical.
- Remove view-time Core Data fetches and relationship graph traversal from presentation code.
- Make feature stores consume explicit query snapshots instead of live managed-object graphs.
- Move write responsibility into `Infrastructure` repositories / writer services.
- Keep compatibility at real external boundaries only:
  - persistent store schema
  - on-disk data
  - ACP protocol behavior
  - user-visible behavior unless intentionally changed

## Non-Goals

- Replacing Core Data.
- Rewriting the entire app in one change.
- Removing every `NSManagedObject` usage in one migration.
- Redesigning UI layout.
- Solving every performance issue with one generic cache layer.

## Core Design Rules

### Rule 1

`NSManagedObject` is an infrastructure concern.

Allowed:

- `Infrastructure` repositories
- `Infrastructure` query controllers
- persistence migrations
- narrowly scoped composition code that immediately maps to snapshots

Not allowed as the default pattern:

- storing `NSManagedObject` directly in feature UI stores
- passing entities through multiple layers as the main read model
- using to-many relationship traversal as a general query strategy in views

### Rule 2

`Application` stores own feature-visible state as plain Swift values.

Examples:

- selected IDs
- visible rows
- counts
- titles
- timeline rows
- filter state
- pending command state

`Application` may reference stable identity by:

- `UUID`
- `NSManagedObjectID` only when strictly needed as an infrastructure bridge

It should not use `ChatSession`, `Worktree`, or `Repository` as the primary observable model.

### Rule 3

Reads and writes must be split.

Use:

- query controllers for read-side snapshots
- repositories / writer services / writer actors for mutations

Do not let the same UI-facing store both:

- mutate Core Data directly
- observe merged managed objects directly

That shape makes invalidation and consistency hard to reason about.

### Rule 4

Each logical mutation should persist in one write boundary.

Examples:

- "send user message" should update session metadata and insert the message in one transaction
- "restore file browser session" should not save after every reopened file
- "switch agent" should not require manual invalidation to make observers catch up

### Rule 5

Views consume projections, not graphs.

A view may receive:

- `ChatSessionRow`
- `RepositorySummary`
- `WorktreeSummary`
- `ActiveTabSummary`
- `PermissionBannerSummary`

It should not fetch from `viewContext` while computing body-time presentation.

### Rule 6

Navigation is explicit coordinator state, not delayed event retry.

If a feature needs to select:

- worktree
- tab
- session

that selection should be represented directly in a coordinator/store model. It should not depend on "post notification after 0.1 seconds and retry later".

## Proposed Architecture

## 1. Introduce feature query controllers

Each feature that currently reads Core Data directly from views or UI stores should gain an `Infrastructure` query layer that maps Core Data changes into plain snapshots.

Suggested shape:

```text
Features/<Feature>/Infrastructure/Persistence/
├── <Feature>QueryController.swift
├── <Feature>SnapshotMapper.swift
└── <Feature>Repository.swift
```

These query controllers may use:

- `NSFetchedResultsController`
- `NSManagedObjectContextObjectsDidChange`
- targeted fetches with controlled refresh rules

Their job is:

- subscribe once
- map once
- publish snapshots to `Application`

They are the correct home for:

- session lists
- active-tab labels
- counts and summary badges
- worktree/repository summary queries

They are not responsible for SwiftUI rendering or user interaction.

## 2. Introduce repositories / writer services as the only mutation boundary

Suggested pattern:

- `ChatSessionRepository`
- `ChatMessageWriter`
- `FileBrowserSessionRepository`
- `WorktreeSessionRepository`
- `WorkspaceRepositoryRepository`

Responsibilities:

- open background writer context
- perform one logical mutation transaction
- save once
- return stable IDs or updated snapshots if needed

Rules:

- feature stores do not call `context.save()` directly as their normal mutation path
- runtime session objects do not create ad hoc background contexts for each persistence fragment
- writes should batch related fields and records together

## 3. Move chat to a runtime-state plus persisted-projection model

Chat currently mixes:

- ACP runtime state
- timeline rendering state
- durable message history
- Core Data session metadata updates

Target shape:

```text
Features/Chat/
├── Domain/
│   ├── ChatTimelineRow.swift
│   ├── ChatSessionSummary.swift
│   └── ChatPersistenceCommand.swift
├── Application/
│   ├── ChatSessionStore.swift
│   ├── ChatTimelineStore.swift
│   └── ChatNavigationStore.swift
├── Infrastructure/
│   ├── ACP/
│   └── Persistence/
│       ├── ChatSessionRepository.swift
│       ├── ChatMessageWriter.swift
│       ├── ChatSessionQueryController.swift
│       └── ChatTimelineSnapshotMapper.swift
└── UI/
```

Design rules:

- `ChatAgentSession` remains runtime-only and ACP-facing
- persistent message commits are sent through `ChatMessageWriter`
- committed messages and tool calls are persisted as one turn-level transaction
- `ChatTimelineStore` owns row updates and should update incrementally rather than via a full epoch invalidation

The main architectural correction is:

- ACP runtime is not the persistent read model
- Core Data entities are not the UI model
- the timeline store is the UI model

## 4. Move workspace/worktree summary reads to snapshot-based read models

Current workspace and worktree views frequently compute:

- counts
- labels
- session lists
- active tab metadata

by traversing relationship sets directly.

Target shape:

- `RepositorySummary`
  - id
  - name
  - note
  - status
  - activeSessionCount
  - visibleWorktreeCount

- `WorktreeSummary`
  - id
  - branch
  - path
  - sessionCounts
  - activeTab
  - status

- `TabSelectionSnapshot`
  - worktreeId
  - selectedTabId
  - selectedSessionIds

The UI should render those summaries directly.

That removes relationship walking from row-view recomputation and makes it possible to dedupe publication semantically.

## 5. Introduce a persistence-safe selection and navigation coordinator

Current navigation logic fetches entities and uses delayed notifications to complete selection.

Target shape:

- one app-level navigation store in `App/`
- feature-level selection stores in `Application/`
- explicit state transitions:
  - selected workspace ID
  - selected repository ID
  - selected worktree ID
  - selected tab ID
  - selected feature session ID

Navigation requests should be idempotent state transitions, not timing-based retries.

## 6. Restrict direct `viewContext` use on the main actor

`viewContext` should be treated as:

- read-mostly
- merge target for background writes
- source for query controllers and short-lived bootstrap reads

It should not be the normal mutation surface for interactive state churn.

Mutation policy:

- user intent enters `Application`
- `Application` calls repository / writer service
- writer service performs background transaction
- query controller observes merged result and publishes updated snapshot

That gives one direction of truth flow:

```text
User intent
-> Application store action
-> Infrastructure writer
-> Core Data save
-> Query controller snapshot update
-> Application store publish
-> UI render
```

## Delivery Shape

This refactor should not land as one giant abstraction pass.

Recommended sequence:

### Phase 1: stop the worst fan-out in Chat

- batch chat persistence into one write transaction per committed message/turn
- replace timeline epoch invalidation with row-level update semantics
- stop doing full-array replacement for every streamed chunk where possible
- move chat session history and metadata reads behind a `ChatSessionQueryController`

### Phase 2: remove Core Data fetches from views

- move `PermissionBannerView` data lookup into a query-backed summary
- move `ActiveTabIndicatorView` title lookup into a query-backed summary
- replace other body-time fetch helpers with `Application` state

### Phase 3: move file browser persistence behind a repository

- make restore/load apply in-memory state first
- coalesce or debounce writes for expansion/open-file persistence
- save once after restore rather than once per restored file

### Phase 4: replace relationship-driven row summaries

- add repository/worktree summary queries
- remove row-level relationship traversal from workspace/worktree presentation helpers

### Phase 5: replace notification-timed navigation

- move tab/session selection into explicit coordinator state
- remove delayed retry notification patterns

## Migration Rules

- New persistence-facing feature work should land under feature `Infrastructure/Persistence/`.
- New UI-facing feature state should land under feature `Application/`.
- Do not introduce new direct `viewContext.fetch()` calls in view helpers unless the fetch is truly one-off bootstrap logic.
- Do not introduce new manual `objectWillChange.send()` calls to compensate for persistence observation gaps.
- Do not add new `NSManagedObject`-typed stored properties to UI stores unless there is a hard external constraint.
- Prefer compile-stable moves and boundary splits before behavior changes.

## Verification

Validation should be both structural and runtime-oriented.

### Structural checks

- No new view-time Core Data fetches in `UI/`.
- No new direct `context.save()` calls in UI stores for normal feature mutations.
- New feature stores publish plain snapshot/value state rather than `NSManagedObject` graphs.
- New navigation flows use explicit state rather than delayed notifications.

### Runtime checks

- Chat streaming does not force full timeline rerender on every chunk.
- One user send produces one persistence transaction for the durable write path.
- Restoring a file browser session does not save once per reopened file.
- Opening workspace/worktree lists does not repeatedly traverse relationship graphs for row counts and labels.
- Background context merges do not trigger manual invalidation to keep screens in sync.

### Profiling checks

Use Instruments or equivalent local profiling to confirm:

- fewer main-thread Core Data fetches during idle redraw and interaction
- fewer merged-change invalidations during chat sends
- fewer SwiftUI body recomputations for row surfaces
- fewer save calls during file browser restore

## Success Criteria

- Persistence writes are predictable, batched, and feature-owned.
- Views do not issue repeat Core Data fetches during normal render.
- Managed objects are no longer the default feature read model.
- Session, tab, and row summaries are delivered through explicit snapshots.
- Chat, workspace, worktree, and files surfaces remain correct under background merges without manual invalidation hacks.
- The architecture matches the feature-first layering policy instead of bypassing it through direct Core Data usage.

## Expected Outcome

After this refactor, Aizen should behave like a system with explicit durable state and explicit runtime/UI state rather than one shared mutable graph trying to serve both roles.

That will not only reduce obvious performance problems.

It will make future work more reliable:

- feature-first migration becomes easier
- state ownership is easier to test
- concurrency boundaries become cleaner
- UI correctness depends less on timing and more on declared data flow
