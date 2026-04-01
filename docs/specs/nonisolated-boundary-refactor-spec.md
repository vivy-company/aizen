# Nonisolated Boundary Refactor

## Summary

Reduce meaningful `nonisolated` usage in Aizen by fixing the underlying type boundaries instead of adding more escape hatches.

This refactor is intentionally narrow. It does not try to remove every `nonisolated` keyword in the codebase. Many current uses are on plain value types, parsers, libgit2 wrappers, or ML model code, and those are not the problem.

The focus is on actor and `@MainActor` types where `nonisolated` is compensating for the wrong responsibility split.

Priority order:

1. `AgentRegistry`
2. `TmuxSessionManager`
3. `GitHostingService`
4. `AgentSession` file I/O boundary

## Project Context

The app target is compiled with:

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

That means `nonisolated` on app-side actor or `@MainActor` types is a real opt-out from the module’s default isolation model.

## Problem Statement

The codebase has many `nonisolated` occurrences, but the important distinction is:

- acceptable uses on plain helpers, immutable data types, or required delegate callbacks
- smell-indicating uses on actor or `@MainActor` types that expose too much sync API or mix pure logic with isolated mutable state

The goal is not “ban `nonisolated`.”

The goal is:

- actors should own serialized mutable state and side effects
- pure transforms should live in plain types
- sync queries should come from immutable snapshots, not by punching holes through actor isolation
- UI/session objects should not own blocking I/O pathways directly

## What Looks Fine Today

These are acceptable and should not drive the refactor:

- immutable value/data models marked `nonisolated`
- plain parser/formatter helpers
- required delegate callbacks that must be callable from nonisolated contexts and immediately hop back to the correct actor
- static constants like [RepositoryManager.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/RepositoryManager.swift)
- background parsing helpers in `@MainActor` stores like [GitDiffRuntimeStore.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/GitDiffRuntimeStore.swift)

## Real Boundary Problems

### 1. `AgentRegistry`

File:

- [AgentRegistry.swift](/Users/uyakauleu/development/aizen/aizen/Services/Agent/AgentRegistry.swift)

Symptoms:

- large cluster of `nonisolated` query methods
- `nonisolated(unsafe) let defaults`
- actor owns both mutable registry state and synchronous read/query APIs
- actor manually maintains a second static cache and lock just to support sync reads

This is the clearest sign that the actor boundary is wrong.

The actor currently acts as all of these at once:

- mutable registry store
- persistence layer
- cache layer
- synchronous read facade
- environment resolution facade
- auth preference facade

That is too much for one actor.

### 2. `TmuxSessionManager`

File:

- [TmuxSessionManager.swift](/Users/uyakauleu/development/aizen/aizen/Services/Terminal/TmuxSessionManager.swift)

Symptoms:

- sync `nonisolated` methods for availability checks and command generation
- actor owns both mutation/cleanup lifecycle and pure command/path logic
- the actor is used partly as a namespace

This suggests two responsibilities are conflated:

- pure tmux environment/command/config description
- serialized runtime operations on real tmux sessions

### 3. `GitHostingService`

File:

- [GitHostingService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/GitHostingService.swift)

Symptoms:

- actor owns cache/stateful CLI probing
- same actor also owns pure provider parsing and browser URL building
- `buildURL` and related helpers are `nonisolated` because they do not belong on the actor in the first place

The actor boundary is too wide.

### 4. `AgentSession` file I/O

File:

- [AgentSession.swift](/Users/uyakauleu/development/aizen/aizen/Services/Agent/AgentSession.swift)

Symptoms:

- `@MainActor` session object exposes `nonisolated` file read/write handlers
- those methods exist to avoid blocking the main actor
- the session object mixes UI/session lifecycle with heavier operational boundaries

This one is less severe than `AgentRegistry`, but it is still a boundary smell.

## Goals

- Remove `nonisolated(unsafe)` from app-side architecture.
- Greatly reduce meaningful `nonisolated` usage on actor and `@MainActor` types.
- Split pure query/build logic away from isolated mutable runtime state.
- Replace sync actor escape hatches with immutable snapshots or plain helper types.
- Keep the resulting architecture simpler, not more layered.

## Non-Goals

- Removing every `nonisolated` keyword in the repo.
- Reworking ML/audio internals as part of this pass.
- Reworking libgit2 wrapper style as part of this pass.
- Changing external behavior or persisted data format unless required.

## Design Principles

- Use actors only for mutable shared state or serialized side effects.
- Use plain `struct`, `enum`, or `final class` types for pure computation and immutable snapshots.
- Prefer explicit snapshot handoff over synchronous `nonisolated` reads from actors.
- If a type needs many sync `nonisolated` methods, it probably should not be an actor in its current shape.
- Do not replace one bad boundary with a larger service-layer stack.

## Proposed Refactors

### Phase 1: `AgentRegistry` split

#### New shape

Split current `AgentRegistry` into:

- `AgentRegistryStore` actor
  - owns mutable registry state
  - owns writes to persistence
  - owns initialization and mutation methods
- `AgentRegistrySnapshot` value type
  - immutable view of agent metadata and preferences
- `AgentRegistryQueries` plain helper
  - pure sync query methods over a snapshot
- `AgentRegistryPersistence` plain helper
  - UserDefaults encoding/decoding

#### Rules

- UI and other synchronous consumers should read from a cached immutable snapshot, not by calling `nonisolated` actor methods.
- Snapshot refresh should happen explicitly after store mutations.
- Environment resolution that requires async shell loading should be separate from sync metadata queries.

#### Remove

- static shared cache lock machinery
- `nonisolated(unsafe) let defaults`
- `nonisolated` query methods on the actor

#### Keep

- one high-level facade named `AgentRegistry` if desired, but it should become a plain `@MainActor` observable coordinator or a thin wrapper around `AgentRegistryStore` plus current snapshot

#### Expected result

- actor becomes small and legitimate
- synchronous reads come from a snapshot
- no unsafe defaults access inside an actor

### Phase 2: `TmuxSessionManager` split

#### New shape

Split into:

- `TmuxRuntime` actor
  - create/kill/list/cleanup sessions
- `TmuxEnvironment` plain helper
  - tmux executable lookup
  - config file path
  - config contents generation
- `TmuxCommandBuilder` plain helper
  - attach/create command construction

#### Remove

- `nonisolated` availability and command-generation methods from the actor

#### Expected result

- actor only owns runtime mutations
- sync command/config logic becomes plain code

### Phase 3: `GitHostingService` split

#### New shape

Split into:

- `GitHostingRuntime` actor
  - CLI path cache
  - auth cache
  - hosting-info cache
  - command execution
- `GitHostingParser` plain helper
  - detect provider from URL
  - parse owner/repo
- `GitHostingURLBuilder` plain helper
  - create PR URL
  - repo URL
  - view PR URL

#### Remove

- `nonisolated` URL-building methods from the actor

#### Expected result

- actor owns only stateful runtime concerns
- pure browser-link logic is fully detached from actor isolation

### Phase 4: `AgentSession` file I/O extraction

#### New shape

Move file read/write request handling out of `AgentSession` into:

- `AgentSessionIOBridge` plain `Sendable` helper or dedicated actor
  - owns file-system delegate routing for ACP file requests

`AgentSession` should forward to that component instead of exposing nonisolated I/O methods itself.

#### Acceptable options

- dedicated actor if there is mutable routing state
- plain helper if it is just delegation

#### Expected result

- `AgentSession` returns to being a UI/session state object
- file I/O boundary is explicit and off-main by design

## Migration Strategy

### Step 1

Implement `AgentRegistry` split first. It gives the biggest architectural win and removes the worst `nonisolated` cluster.

### Step 2

Split `TmuxSessionManager`. This is a low-risk cleanup with clear responsibility boundaries.

### Step 3

Split `GitHostingService`. This is mostly extraction of pure code from actor code.

### Step 4

Extract file I/O from `AgentSession` if Phase 1–3 remain clean and the session surface still looks too broad.

## Verification

For each phase:

- Build the app.
- Search for remaining `nonisolated` uses in the touched subsystem.
- Confirm that any remaining `nonisolated` is either:
  - required by delegate conformance
  - a static constant
  - on a plain helper/value type rather than an actor escape hatch

Suggested checks:

- `rg -n "\\bnonisolated\\b" aizen/Services/Agent`
- `rg -n "\\bnonisolated\\b" aizen/Services/Terminal`
- `rg -n "\\bnonisolated\\b" aizen/Services/Git/GitHostingService.swift`
- `xcodebuild -project /Users/uyakauleu/development/aizen/aizen.xcodeproj -scheme aizen -configuration Debug -sdk macosx build`

## Success Criteria

- `AgentRegistry` no longer relies on `nonisolated(unsafe)` or a static lock-backed shadow cache.
- `TmuxSessionManager` actor only owns runtime mutations.
- `GitHostingService` actor no longer contains pure URL-building logic.
- `AgentSession` no longer needs `nonisolated` file read/write entry points, or those are isolated in a dedicated I/O boundary.
- Remaining `nonisolated` usage in these subsystems is small, deliberate, and easy to justify.
