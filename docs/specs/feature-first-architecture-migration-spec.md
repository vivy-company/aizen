# Aizen Feature-First Architecture Migration Spec

## Summary

Refactor Aizen incrementally toward a feature-first structure with explicit internal layers:
- `Domain`
- `Application`
- `Infrastructure`
- `UI`

This is an architectural migration strategy for the app, not a single giant repo rewrite.

The migration is intentionally incremental:
- move one substantial feature at a time
- keep each feature refactor behavior-preserving by default
- avoid temporary legacy wrappers when cutting a feature over
- allow the rest of the app to remain in the current structure until its feature is migrated

The immediate goal is to make new work land in the target architecture from the start instead of creating more work inside the legacy buckets.

## Problem

The current Aizen structure is heavily organized around top-level technical buckets:
- `Models/`
- `Services/`
- `Views/`
- `Managers/`
- `Utilities/`

That structure is now working against the app in several areas:
- feature logic is scattered across multiple unrelated top-level folders
- non-UI stateful logic lives under `Views/`
- `Manager` and `Service` types have inconsistent meaning
- large ownership centers have formed around a few oversized files
- view models and runtime coordinators often mix persistence, orchestration, transport, and presentation concerns
- it is difficult to grow substantial features without increasing coupling

Current examples of architectural pressure include:
- `aizen/Views/ContentView.swift`
- `aizen/Services/Git/RepositoryManager.swift`
- `aizen/Services/Agent/AgentSession.swift`
- `aizen/Views/Chat/ChatSessionViewModel.swift`
- `aizen/Views/Worktree/WorktreeDetailView.swift`
- `aizen/Views/Browser/BrowserSessionManager.swift`

## Goals

- Move Aizen toward a feature-first architecture incrementally.
- Make new feature work land directly in the target structure.
- Preserve user-visible behavior during structural refactors unless a behavior correction is explicitly intended.
- Reduce cross-feature coupling.
- Establish clearer ownership boundaries inside features.
- Make state orchestration testable without SwiftUI and without live external integrations where practical.
- Eliminate the need for vague top-level buckets as the default placement for new work.

## Non-Goals

- Rewriting the entire app into the new architecture in one change.
- Redesigning the UI as part of the structural migration.
- Changing product scope under the guise of architecture work.
- Introducing compatibility shims purely to preserve the legacy internal structure.
- Extracting every shared utility up front before feature migrations begin.

## Migration Strategy

This migration is feature-by-feature, not repo-wide all at once.

Recommended order:
1. `Chat`
2. `Worktree`
3. `Repository`
4. `Browser`
5. `Files`
6. `Settings`
7. other supporting areas as needed

For each feature:
1. create the feature subtree
2. move files with minimal behavior changes
3. split domain, application, infrastructure, and UI ownership
4. update integration points to use the feature entry point
5. remove the legacy implementation for that feature in the same cutover

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

## Feature Internal Structure

Each migrated feature should follow this internal shape unless there is a strong reason not to:

```text
FeatureName/
├── Domain/
├── Application/
├── Infrastructure/
├── UI/
└── Testing/
```

### Domain

Contains pure feature types and rules.

Rules:
- no SwiftUI
- no AppKit
- no Core Data fetch logic
- no networking/process/ACP/libgit2/WebKit/Ghostty ownership

Examples:
- feature data models
- value types
- policy types
- feature errors
- sorting/filtering/path/state models

### Application

Contains feature state and use-case orchestration.

Rules:
- may be `@MainActor` when it owns UI-facing state
- depends on `Domain`
- depends on protocols or adapters from `Infrastructure`
- does not own SwiftUI layout

Examples:
- stores
- coordinators
- action handlers
- session registries
- feature persistence orchestration

### Infrastructure

Contains real implementations of external integrations and storage.

Rules:
- may depend on Core Data, ACP, libgit2, WebKit, Ghostty, filesystem, UserDefaults, Xcode, etc.
- must not contain SwiftUI screen logic
- should hide external implementation details from `Application`

Examples:
- ACP adapters
- Core Data repositories
- libgit2 adapters
- WebKit adapters
- filesystem services
- temp storage and persistence implementations

### UI

Contains presentation only.

Rules:
- no transport logic
- no persistence orchestration
- no recursive mutation logic
- no external system ownership

Examples:
- screens
- view composition
- components
- sheets
- platform-specific presentation wrappers

## Current Transitional Rules

Until the full app is migrated, Aizen will operate in a mixed architecture:
- legacy top-level buckets still exist
- migrated features live under `Features/`
- new work for a migrated feature must stay inside that feature subtree
- new substantial work for an unmigrated feature should prefer creating the target feature subtree instead of expanding legacy buckets further

This means:
- do not add new broad `Manager` types when a feature store/coordinator is the real ownership boundary
- do not place non-view feature state in `Views/`
- do not place feature-specific orchestration in `Utilities/`
- do not default to `Services/` for all new business logic

## Initial Feature Targets

### Chat

Target shape:

```text
Features/Chat/
├── Domain/
├── Application/
├── Infrastructure/
├── UI/
└── Testing/
```

Likely migration candidates:
- `Views/Chat/*`
- `Services/Agent/*` pieces that are chat-session specific
- `Models/Chat/*`
- selected persistence code currently coupled directly to chat runtime

### Worktree

Target shape:

```text
Features/Worktree/
├── Domain/
├── Application/
├── Infrastructure/
├── UI/
└── Testing/
```

Likely migration candidates:
- `Views/Worktree/*`
- `Services/Worktree/*`
- worktree-specific orchestration currently mixed into git/xcode/session management

### Repository

Target shape:

```text
Features/Repository/
├── Domain/
├── Application/
├── Infrastructure/
├── UI/
└── Testing/
```

Likely migration candidates:
- `Services/Git/RepositoryManager.swift`
- repository import/clone/scan/relocation responsibilities
- repository-facing UI such as add/create/import flows

## Safe Refactor Rules

For feature migration PRs, default expectations are:
- no intentional UI redesign
- no intentional UX change
- no intentional navigation changes
- no intentional feature-scope changes

Allowed:
- moving files
- renaming types for ownership clarity
- splitting large files
- introducing protocols at the feature boundary
- replacing singleton-heavy feature state with injected dependencies
- consolidating persistence/temporary-state ownership when behavior remains equivalent

Not allowed unless explicitly part of the task:
- aesthetic redesign
- broad workflow changes
- adding new capabilities under the guise of cleanup
- maintaining both old and new feature ownership paths in parallel

## Dependency Injection Direction

Feature boundaries should move toward dependency injection.

Target pattern:
- app integration layer composes feature dependencies
- feature entry point receives stores/services explicitly
- infrastructure implementations stay behind feature-local protocols or adapters
- tests can build the feature without global singletons where practical

Temporary compatibility is acceptable only at genuine external boundaries.
It is not acceptable to keep internal duplicate ownership models just to avoid touching call sites.

## Testing Direction

As features migrate, add feature-scoped tests under:

```text
aizenTests/
└── Features/
    └── FeatureName/
```

Prioritize tests for:
- domain rules
- application stores/coordinators
- persistence mapping
- feature-specific behavior that was previously trapped inside view models or broad managers

## Migration Decision Rules

When touching an area of the app, use this decision order:

1. If the feature already exists under `Features/`, keep new work inside that subtree.
2. If the feature is clearly substantial and currently scattered, prefer creating its `Features/<Name>/` subtree now.
3. If the change is tiny and the feature is not ready for migration, a legacy-location edit is acceptable, but do not deepen the old structure unnecessarily.
4. If a file is already an oversized ownership center, split responsibility instead of adding more code to it.

## Expected Outcome

The goal is not a one-time architectural rewrite.

The goal is:
- every new substantial change improves the structure
- migrated features become self-contained and easier to evolve
- the legacy top-level buckets shrink over time
- future contributors can work feature-locally instead of mentally reconstructing cross-repo wiring
