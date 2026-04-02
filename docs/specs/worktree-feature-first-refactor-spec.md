# Aizen Worktree Feature-First Refactor Spec

## Summary

Refactor the Worktree feature into:
- `Domain`
- `Application`
- `Infrastructure`
- `UI`

This is a behavior-preserving structural refactor by default.

## Current Problem

Worktree behavior is currently spread across:
- `aizen/Views/Worktree/*`
- `aizen/Services/Worktree/*`
- worktree runtime coordination mixed into Git, Xcode, Chat, and tab/session management

The feature boundary is real in the product but weak in the code.

## Goals

- make Worktree the primary owner of worktree detail/runtime state
- centralize worktree-level session/tab orchestration
- isolate runtime registry behavior from SwiftUI views
- keep Git/Xcode/Chat/Files/Browser integrations thin at the worktree boundary

## Target Structure

```text
Features/Worktree/
├── Domain/
│   ├── WorktreeItem.swift
│   ├── WorktreeSelection.swift
│   ├── WorktreeSessionTab.swift
│   └── WorktreeDetailState.swift
├── Application/
│   ├── WorktreeDetailStore.swift
│   ├── WorktreeSelectionCoordinator.swift
│   ├── WorktreeRuntimeRegistry.swift
│   ├── WorktreeSessionCoordinator.swift
│   └── WorktreePersistence.swift
├── Infrastructure/
│   ├── CoreDataWorktreeRepository.swift
│   ├── GitSummaryAdapter.swift
│   ├── WorkflowServiceAdapter.swift
│   ├── XcodeBuildAdapter.swift
│   └── FileSearchAdapter.swift
├── UI/
│   ├── WorktreeListScreen.swift
│   ├── WorktreeDetailScreen.swift
│   ├── Components/
│   ├── Git/
│   ├── Workflow/
│   └── Xcode/
└── Testing/
```

## Mapping Direction

Likely migration candidates:
- `Views/Worktree/WorktreeDetailView.swift`
- `Views/Worktree/WorktreeListView.swift`
- `Views/Worktree/Components/*`
- `Services/Worktree/WorktreeRuntimeCoordinator.swift`
- selected tab/session coordination currently in view-layer helpers

## Key Rules

- `WorktreeDetailStore` should own current selected tab/session state, not the screen.
- runtime registry/coordination belongs in `Application`, not `UI`.
- feature UI composes Chat/Terminal/Files/Browser entry points but does not own their internals.

## Must Preserve

- current worktree detail layout
- current tab structure and toolbar behavior
- current Git panel integration
- current Xcode integration entry points
- current file search/open behavior

## Migration Phases

1. create `Features/Worktree/`
2. move Worktree views into `UI/`
3. extract `WorktreeDetailStore` and `WorktreeSessionCoordinator`
4. move runtime coordination out of view construction
5. add tests for selection/runtime orchestration
