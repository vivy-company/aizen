# Aizen Files Feature-First Refactor Spec

## Summary

Refactor Files into:
- `Domain`
- `Application`
- `Infrastructure`
- `UI`

## Current Problem

Files behavior currently mixes:
- file-browser state
- Core Data session persistence
- git runtime state
- file IO/editing concerns
- SwiftUI presentation

## Goals

- isolate file-browser state from presentation
- centralize file session persistence and editor state ownership
- keep file UI behavior stable
- make git/file integration explicit at the feature boundary

## Target Structure

```text
Features/Files/
├── Domain/
│   ├── FileNode.swift
│   ├── OpenFileModel.swift
│   ├── FileBrowserState.swift
│   └── FileBrowserError.swift
├── Application/
│   ├── FileBrowserStore.swift
│   ├── FileEditorStore.swift
│   ├── FileBrowserPersistence.swift
│   └── FileGitStateCoordinator.swift
├── Infrastructure/
│   ├── CoreDataFileBrowserRepository.swift
│   ├── LocalFileSystemAdapter.swift
│   ├── FileServiceAdapter.swift
│   └── GitRuntimeAdapter.swift
├── UI/
│   ├── FileBrowserScreen.swift
│   ├── Components/
│   └── Editors/
└── Testing/
```

## Must Preserve

- current file tree behavior
- current open tab behavior
- current file content editing behavior
- current git status decoration behavior

## Migration Phases

1. create feature subtree
2. move Files views into `UI/`
3. extract browser/editor state into stores
4. isolate persistence and git adapters
5. add tests for path/session/editor state
