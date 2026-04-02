# Aizen Feature-First Refactor TODO

## Repo-Level

- [ ] adopt `docs/specs/complete-feature-first-refactor-roadmap.md` as the parent roadmap
- [ ] keep `AGENTS.md` aligned with the migration rules
- [ ] prefer atomic commits for all migration work
- [ ] avoid new broad top-level `Manager` types
- [ ] avoid new feature orchestration under `Views/`

## Chat

- [ ] create `Features/Chat/`
- [ ] move Chat UI files into `Features/Chat/UI/`
- [ ] extract `ChatSessionStore`
- [ ] split ACP runtime from UI-facing chat state
- [ ] add `aizenTests/Features/Chat/`

## Worktree

- [ ] create `Features/Worktree/`
- [ ] move Worktree UI files into `Features/Worktree/UI/`
- [ ] extract `WorktreeDetailStore`
- [ ] extract `WorktreeSessionCoordinator`
- [ ] add `aizenTests/Features/Worktree/`

## Repository

- [ ] create `Features/Repository/`
- [ ] decompose `RepositoryManager`
- [ ] separate persistence from repository orchestration
- [ ] add repository feature tests

## Browser

- [ ] create `Features/Browser/`
- [ ] replace `BrowserSessionManager` with `BrowserSessionStore`
- [ ] isolate WebKit integration in infrastructure
- [ ] add browser feature tests

## Files

- [ ] create `Features/Files/`
- [ ] extract file browser/editor stores
- [ ] isolate file persistence and git adapters
- [ ] add files feature tests

## Terminal

- [ ] create `Features/Terminal/`
- [ ] isolate Ghostty/tmux infrastructure
- [ ] extract terminal session and split coordinators
- [ ] add terminal feature tests

## Workspace

- [ ] create `Features/Workspace/`
- [ ] thin `ContentView` by moving workspace selection state out
- [ ] isolate workspace selection persistence
- [ ] add workspace feature tests

## Settings and Search

- [ ] create `Features/Settings/`
- [ ] create `Features/Search/`
- [ ] move settings/search state ownership out of UI/controller-heavy code
- [ ] add tests where stateful behavior is extracted

## Cleanup

- [ ] shrink legacy usage of `Views/`, `Services/`, `Managers/`, and `Models/` as features migrate
- [ ] move shared platform wrappers into `Platform/`
- [ ] move cross-feature integrations into `Integrations/`
- [ ] keep shared generic code in `Shared/`
