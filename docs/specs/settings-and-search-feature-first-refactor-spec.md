# Aizen Settings and Search Feature-First Refactor Spec

## Summary

Refactor Settings and Search into explicit feature ownership trees.

These areas are lower priority than Chat, Worktree, Repository, Browser, Files, and Terminal, but should follow the same architecture once core migrations are underway.

## Goals

- keep settings state out of scattered window/controller helpers
- make search behavior and UI easier to test and evolve
- preserve current settings sections and search entry points

## Target Structure

```text
Features/Settings/
├── Domain/
├── Application/
├── Infrastructure/
├── UI/
└── Testing/

Features/Search/
├── Domain/
├── Application/
├── Infrastructure/
├── UI/
└── Testing/
```

## Settings Direction

Likely migration candidates:
- `Views/Settings/*`
- `Managers/SettingsWindowManager.swift`
- settings-specific storage/helpers currently scattered across managers and services

Must preserve:
- current settings window structure
- current section split
- current deep-link/open-settings flows

## Search Direction

Likely migration candidates:
- `Views/Search/*`
- `Services/Search/*`

Must preserve:
- current file search entry points
- current window/controller behavior
- current result opening flows
