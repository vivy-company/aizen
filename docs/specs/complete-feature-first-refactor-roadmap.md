# Aizen Complete Feature-First Refactor Roadmap

## Summary

Refactor Aizen incrementally into a feature-first architecture with explicit internal layers:
- `Domain`
- `Application`
- `Infrastructure`
- `UI`

This roadmap covers the full app migration. It is the parent document for the feature-specific specs.

The migration must remain incremental:
- one feature at a time
- compile-stable steps where possible
- behavior-preserving by default
- no repo-wide compatibility scaffolding that preserves the old ownership model

## Scope

This roadmap covers:
- app-level composition rules
- top-level target structure
- migration order
- feature cutover rules
- testing and rollout expectations

Detailed feature requirements live in:
- `chat-feature-first-refactor-spec.md`
- `worktree-feature-first-refactor-spec.md`
- `repository-feature-first-refactor-spec.md`
- `browser-feature-first-refactor-spec.md`
- `files-feature-first-refactor-spec.md`
- `terminal-feature-first-refactor-spec.md`
- `workspace-feature-first-refactor-spec.md`
- `settings-and-search-feature-first-refactor-spec.md`

## Problem

Aizen currently mixes:
- feature logic across `Views/`, `Services/`, `Models/`, `Managers/`, and `Utilities/`
- UI concerns with persistence and orchestration
- app-global coordination with feature-local runtime state
- platform wrappers with domain behavior

This is manageable for small features, but it is now a liability for large ones such as Chat, Worktree, Repository management, Browser, and Terminal.

## Goals

- Make feature ownership local and obvious.
- Split pure feature rules from orchestration and external integrations.
- Reduce growth pressure on oversized files and broad managers.
- Make new work land in the target architecture immediately.
- Migrate the app without forcing a single destabilizing rewrite.

## Non-Goals

- visual redesign
- user-flow redesign
- changing product scope
- extracting every possible shared abstraction up front
- preserving old internal shapes for convenience

## Target Top-Level Structure

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

## Feature Internal Shape

```text
FeatureName/
├── Domain/
├── Application/
├── Infrastructure/
├── UI/
└── Testing/
```

### Domain
- pure feature types
- value types
- policy rules
- feature-level errors

### Application
- stores
- coordinators
- use-case orchestration
- feature state ownership

### Infrastructure
- Core Data adapters
- ACP/libgit2/Ghostty/WebKit/Xcode/filesystem implementations
- integration adapters

### UI
- screens
- presentation components
- sheets
- platform-specific presentation wrappers

## App-Level Rules

### App

`App/` owns:
- app entry
- dependency composition
- app-wide routing
- window/session coordination at the app boundary
- command registration
- deep linking

`App/` does not own:
- feature business logic
- feature runtime state beyond integration wiring

### Platform

`Platform/` owns reusable wrappers around concrete technologies:
- Ghostty
- libgit2
- Xcode
- audio engines
- Sparkle

### Integrations

`Integrations/` owns cross-feature external integrations:
- ACP
- MCP
- GitHub/GitLab workflow integration
- agent registries where shared across features

### Persistence

`Persistence/` owns:
- Core Data stack
- schema
- persistence helpers reused across features

Feature-specific persistence adapters may still live under the feature `Infrastructure/` layer.

### Shared

`Shared/` owns:
- design system
- reusable controls
- generic utilities
- logging/helpers used across many features

Feature-specific code does not belong here.

## Migration Order

Recommended order:
1. Chat
2. Worktree
3. Repository
4. Browser
5. Files
6. Terminal
7. Workspace
8. Settings and Search
9. shared platform/integration cleanup

Rationale:
- Chat and Worktree currently have the highest architectural pressure.
- Repository is a core ownership boundary that unblocks later cleanup.
- Browser, Files, and Terminal are strong feature boundaries with mixed state/orchestration today.
- Workspace and Settings/Search become cleaner after the core feature migrations settle.

## Migration Phases Per Feature

### Phase 1: Create Feature Tree
- create `Features/<Feature>/`
- move files with minimal behavior change
- keep type names stable where sensible

### Phase 2: Split Ownership
- identify domain models
- separate stateful orchestration into `Application`
- isolate external integrations in `Infrastructure`
- keep `UI` presentation-only

### Phase 3: Cut Over Integration
- update parent containers to compose the feature entry point directly
- remove legacy ownership for that feature

### Phase 4: Add Tests
- add domain tests
- add application/store tests
- add critical integration tests where the feature behavior is sensitive

## Safe Refactor Contract

Default expectation for migration PRs:
- no intentional UI redesign
- no intentional UX change
- no intentional navigation redesign
- no intentional scope expansion

Allowed:
- file moves
- type renames for ownership clarity
- dependency injection
- replacing singletons with feature composition where behavior is preserved
- consolidating persistence/temp-state ownership

Not allowed unless explicitly specified:
- new feature work hidden inside structural PRs
- old/new dual ownership for the same feature
- broad visual or workflow changes

## Atomic Commit Guidance

Commits should usually follow this pattern:
1. create feature tree and compile-stable file moves
2. adjust imports and integration points
3. split responsibilities into layer ownership
4. add tests

Do not mix unrelated cleanup into feature migration commits.

## Testing Expectations

Each feature migration should add tests under:

```text
aizenTests/
└── Features/
    └── <Feature>/
```

At minimum:
- domain rules
- application state/store behavior
- narrow integration tests for persistence or protocol adapters

## Completion Criteria

The app refactor is complete when:
- substantial feature code lives under `Features/`
- app-global composition is concentrated in `App/`
- broad new `Manager` types are no longer being introduced
- non-view feature orchestration no longer lives under `Views/`
- legacy top-level buckets are either minimized or limited to unmigrated areas only
