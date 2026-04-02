# Aizen Terminal Feature-First Refactor Spec

## Summary

Refactor Terminal into:
- `Domain`
- `Application`
- `Infrastructure`
- `UI`

## Current Problem

Terminal behavior spans:
- `GhosttyTerminal/*`
- `Views/Terminal/*`
- `Managers/Terminal*`
- `Services/Terminal/*`

The product boundary is a feature, but the implementation is split by technology and helper buckets.

## Goals

- make terminal session/split ownership explicit
- keep Ghostty as platform infrastructure, not feature state owner
- preserve current split-pane and session behavior

## Target Structure

```text
Features/Terminal/
├── Domain/
│   ├── TerminalSessionState.swift
│   ├── TerminalSplitTree.swift
│   └── TerminalPresetModel.swift
├── Application/
│   ├── TerminalSessionStore.swift
│   ├── TerminalSplitCoordinator.swift
│   ├── TerminalPresetStore.swift
│   └── TerminalTitleRegistry.swift
├── Infrastructure/
│   ├── GhosttyTerminalAdapter.swift
│   ├── TmuxSessionAdapter.swift
│   └── TerminalPersistenceAdapter.swift
├── UI/
│   ├── TerminalTabView.swift
│   ├── Components/
│   └── Platform/
└── Testing/
```

## Must Preserve

- current terminal tab behavior
- current split-pane behavior
- current preset behavior
- current Ghostty-backed rendering and session flows

## Migration Notes

- `GhosttyTerminal/` likely becomes `Platform/Ghostty/` over time.
- feature state should not remain trapped in view/controller helpers.
