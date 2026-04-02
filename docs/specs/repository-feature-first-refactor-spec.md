# Aizen Repository Feature-First Refactor Spec

## Summary

Refactor repository and repository-management behavior into a `Repository` feature with:
- `Domain`
- `Application`
- `Infrastructure`
- `UI`

## Current Problem

Repository ownership is concentrated in broad services such as:
- `aizen/Services/Git/RepositoryManager.swift`

Current responsibilities mixed together:
- workspace/repository CRUD
- repository import/clone/scan
- path normalization
- worktree bootstrapping
- filesystem/open-in-app helpers
- post-create logic

## Goals

- split repository concerns into explicit use cases
- isolate Core Data persistence from repository orchestration
- keep repository UI flows thin
- make import/clone/relocation behavior easier to evolve safely

## Target Structure

```text
Features/Repository/
├── Domain/
│   ├── RepositoryItem.swift
│   ├── RepositoryPath.swift
│   ├── RepositoryImportRequest.swift
│   ├── RepositoryRelocation.swift
│   └── RepositoryError.swift
├── Application/
│   ├── RepositoryCatalogStore.swift
│   ├── RepositoryImportService.swift
│   ├── RepositoryRelocationService.swift
│   ├── RepositoryScanner.swift
│   └── WorktreeProvisioningService.swift
├── Infrastructure/
│   ├── CoreDataRepositoryRepository.swift
│   ├── GitRepositoryProbe.swift
│   ├── RemoteCloneAdapter.swift
│   ├── RepositoryFileSystemAdapter.swift
│   └── PostCreateActionAdapter.swift
├── UI/
│   ├── RepositoryAddSheet.swift
│   ├── Components/
│   └── Integration/
└── Testing/
```

## Mapping Direction

- `RepositoryManager.swift` should be decomposed, not moved intact.
- low-level git operations stay in git/platform/infrastructure ownership.
- repository UI sheets remain behavior-compatible.

## Must Preserve

- add existing repository flow
- clone flow
- relocate flow
- worktree scanning behavior
- current workspace association behavior

## Migration Phases

1. create feature subtree
2. extract domain types and persistence adapters
3. split `RepositoryManager` by use case
4. update UI integration points
5. remove legacy repository manager ownership
