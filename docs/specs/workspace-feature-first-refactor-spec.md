# Aizen Workspace Feature-First Refactor Spec

## Summary

Refactor Workspace into:
- `Domain`
- `Application`
- `Infrastructure`
- `UI`

## Current Problem

Workspace selection and root-shell behavior are concentrated in app/root views, especially:
- `aizen/Views/ContentView.swift`

That makes app-shell and workspace/repository/worktree selection hard to evolve cleanly.

## Goals

- separate app shell from workspace feature state
- isolate selection persistence and navigation behavior
- preserve current sidebar structure and onboarding interactions

## Target Structure

```text
Features/Workspace/
├── Domain/
│   ├── WorkspaceItem.swift
│   ├── WorkspaceSelection.swift
│   └── WorkspaceError.swift
├── Application/
│   ├── WorkspaceListStore.swift
│   ├── WorkspaceSelectionCoordinator.swift
│   ├── WorkspaceNavigationState.swift
│   └── WorkspacePersistence.swift
├── Infrastructure/
│   ├── CoreDataWorkspaceRepository.swift
│   └── WorkspaceSelectionStorage.swift
├── UI/
│   ├── WorkspaceSidebarView.swift
│   ├── WorkspaceCreateSheet.swift
│   ├── WorkspaceEditSheet.swift
│   └── Components/
└── Testing/
```

## Must Preserve

- current workspace sidebar behavior
- current persistent selection behavior
- current onboarding and cross-project entry points

## Migration Notes

- `ContentView` should get thinner as workspace selection and persistence move into the feature.
- app root should compose the workspace feature instead of owning its internals.
