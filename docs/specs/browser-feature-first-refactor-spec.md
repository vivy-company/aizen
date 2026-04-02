# Aizen Browser Feature-First Refactor Spec

## Summary

Refactor Browser into:
- `Domain`
- `Application`
- `Infrastructure`
- `UI`

## Current Problem

Browser state is currently managed by a type under `Views/`:
- `aizen/Views/Browser/BrowserSessionManager.swift`

That type mixes:
- Core Data persistence
- tab/session state
- WebView ownership
- navigation actions
- UI-facing published state

## Goals

- move non-view browser state out of `Views/`
- isolate WebKit integration from feature state orchestration
- make browser session persistence testable
- preserve browser UI and tab behavior

## Target Structure

```text
Features/Browser/
├── Domain/
│   ├── BrowserSessionState.swift
│   ├── BrowserNavigationState.swift
│   └── BrowserError.swift
├── Application/
│   ├── BrowserSessionStore.swift
│   ├── BrowserNavigationCoordinator.swift
│   └── BrowserPersistence.swift
├── Infrastructure/
│   ├── CoreDataBrowserSessionRepository.swift
│   └── WebKitBrowserAdapter.swift
├── UI/
│   ├── BrowserTabView.swift
│   ├── Components/
│   └── Platform/
└── Testing/
```

## Must Preserve

- current browser tab behavior
- current navigation controls
- current URL/title persistence
- current load state reporting

## Migration Phases

1. create feature subtree
2. replace `BrowserSessionManager` with `BrowserSessionStore`
3. isolate WebKit ownership into infrastructure
4. update Browser UI to bind to injected store
5. add tests for persistence and navigation state transitions
