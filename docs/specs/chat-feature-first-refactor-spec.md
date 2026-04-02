# Aizen Chat Feature-First Refactor Spec

## Summary

Refactor Aizen Chat into a feature-first structure with:
- `Domain`
- `Application`
- `Infrastructure`
- `UI`

This is a structural refactor. Default expectation is behavior preservation.

## Current Problem

Chat behavior is currently split across:
- `aizen/Views/Chat/*`
- `aizen/Services/Agent/*`
- `aizen/Models/Chat/*`
- selected persistence code

This causes:
- chat UI and chat runtime logic to be interleaved
- ACP session state to be exposed too directly to presentation
- persistence, streaming aggregation, permissions, auth, and tool-call coordination to live across unrelated folders

## Goals

- make Chat a self-contained feature subtree
- separate transcript/domain types from runtime orchestration
- isolate ACP transport/runtime details from UI
- make chat stores and timeline building testable without SwiftUI
- preserve current Chat tab behavior and session flows

## Non-Goals

- redesigning chat UI
- changing message rendering behavior intentionally
- changing current agent capabilities or flows

## Target Structure

```text
Features/Chat/
├── Domain/
│   ├── ChatMessage.swift
│   ├── ChatTimelineItem.swift
│   ├── ChatAttachmentModel.swift
│   ├── ChatToolCallModel.swift
│   ├── ChatSessionState.swift
│   └── ChatError.swift
├── Application/
│   ├── ChatSessionStore.swift
│   ├── ChatComposerStore.swift
│   ├── ChatTimelineBuilder.swift
│   ├── ChatPermissionCoordinator.swift
│   ├── ChatSessionPersistence.swift
│   └── ChatSessionRegistry.swift
├── Infrastructure/
│   ├── ACPChatClient.swift
│   ├── ACPProcessSupervisor.swift
│   ├── ACPToolCallTracker.swift
│   ├── CoreDataChatRepository.swift
│   ├── AgentRegistryProvider.swift
│   └── AudioTranscriptionAdapter.swift
├── UI/
│   ├── ChatSessionScreen.swift
│   ├── ChatTabView.swift
│   ├── Components/
│   ├── Sheets/
│   └── Helpers/
└── Testing/
```

## Mapping Direction

Likely starting points:
- `Views/Chat/ChatSessionViewModel.swift` -> `Application/ChatSessionStore.swift`
- `Views/Chat/ChatSessionView.swift` -> `UI/ChatSessionScreen.swift`
- `Views/Chat/ChatTabView.swift` -> `UI/ChatTabView.swift`
- `Services/Agent/AgentSession.swift` -> split between `Application` and `Infrastructure`
- `Services/Agent/Delegates/*` -> `Infrastructure`
- `Models/Chat/*` -> `Domain`

## Layer Rules

### Domain
- no SwiftUI
- no ACP client ownership
- no Core Data fetches

### Application
- owns current session state exposed to UI
- owns send/retry/resume/auth/setup/update orchestration
- builds timeline state for presentation

### Infrastructure
- owns ACP process/client integration
- owns persistence adapters
- owns agent-registry and audio bridge adapters needed by Chat

### UI
- presentation only
- no ACP lifecycle management
- no persistence fetching logic

## Safe Refactor Rules

Must preserve:
- current Chat tab integration
- current session switching behavior
- current streaming behavior
- current permission/auth/setup/update flows
- current attachments and inline diff flows
- current voice-input entry points

## Migration Phases

### Phase 1
- create `Features/Chat/`
- move current Chat view files into `UI/`
- move chat models into `Domain/`

### Phase 2
- extract `ChatSessionStore` from `ChatSessionViewModel`
- extract timeline building and permission/auth orchestration

### Phase 3
- split `AgentSession` responsibilities into chat runtime application state vs ACP infrastructure

### Phase 4
- wire Chat feature through app integration points
- remove legacy chat ownership

### Phase 5
- add tests for timeline building, state transitions, and persistence behavior
