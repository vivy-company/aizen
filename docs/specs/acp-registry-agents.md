# ACP Registry Agents Spec

## Goal

Move Aizen to an ACP-registry-first agent model.

Built-in agents should be removed as a separate product concept. Aizen should consume agents from the official ACP registry plus user-defined custom agents.

The first visible change in Settings should be a new sidebar action placed before `Add Custom Agent`:

- `Add From Registry`
- `Add Custom Agent`

## Investigation Summary

### Current Aizen behavior

- The Settings sidebar has a static `Add Custom Agent` row and no registry-backed discovery flow.
- `AgentMetadata` currently models two effective classes of agents:
  - built-in curated agents (`isBuiltIn == true`)
  - user-defined custom agents (`isBuiltIn == false`)
- Install UI is effectively built-in-only today:
  - `SettingsView` only exposes built-in entries plus the custom-agent button.
  - `AgentDetailView` only shows the `Install` action when `metadata.isBuiltIn` is true.
- Validation assumes every agent resolves to a concrete executable file on disk:
  - `AgentRegistry.validateAgent(named:)` checks `fileExists(atPath:)` and `isExecutableFile(atPath:)`.
- Launch also assumes a real executable path:
  - Aizen passes `agentPath` directly into `ACP.Client.launch(...)`.
  - `swift-acp`'s process manager uses `Process.executableURL = URL(fileURLWithPath: agentPath)`, so bare commands like `npx` are not safely supported as-is.

### Upstream ACP registry behavior

- The pinned `swift-acp` revision already ships an `ACPRegistry` product.
- `RegistryClient` fetches the official registry from:
  - `https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json`
- Registry agents can distribute through:
  - `binary`
  - `npx`
  - `uvx`
- `ACPRegistry.AgentInstaller` is useful, but its return type is not a drop-in fit for Aizen:
  - binary installs return an extracted executable path
  - `npx` installs return `executablePath: "npx"`
  - `uvx` installs return `executablePath: "uvx"`
- That means Aizen cannot just persist the upstream `InstalledAgent` payload unchanged, because current validation and launch paths expect an absolute executable path.

### Important compatibility finding

Registry integration is not just a new picker UI.

The main architectural gap is that Aizen currently models "installed agent" as "absolute executable on disk", while the ACP registry also models command-based launches (`npx`, `uvx`).

## Scope

### In scope

- Replace the built-in agent catalog with registry-backed agents.
- Seed Aizen with three default registry-backed agents:
  - Claude Code
  - Codex
  - OpenCode
- Add a new `Add From Registry` entry in Settings before `Add Custom Agent`.
- Fetch and display the official ACP registry.
- Let users add a registry agent into Aizen's Settings.
- Support launching registry agents distributed as:
  - binary
  - npx
  - uvx
- Show registry metadata in agent detail UI.
- Support removing a registry-imported agent from Aizen.
- Support update detection for registry-imported agents.

### Out of scope

- Background auto-sync of registry updates without user action.

## Proposed Design

### 1. Collapse built-ins into registry-backed agents

Replace the current built-in/custom split with:

- `registry`
- `custom`

Recommended shape:

- Add `source: AgentSource` to `AgentMetadata`
- Stop using `isBuiltIn` for runtime behavior
- Remove `AgentInstallMethod` as the primary model for managed agents

Suggested registry payload:

- `registryId: String`
- `registryVersion: String`
- `repositoryURL: String?`
- `iconURL: String?`
- `distributionType: RegistryDistributionType`

This is needed so Aizen can:

- render source-specific UI
- compare installed metadata to the latest registry entry
- refresh launch arguments and environment when the registry changes

### 2. Introduce a first-class launch model

Refactor Aizen away from "every agent is an absolute executable on disk".

Add an explicit launch descriptor to `AgentMetadata`, for example:

- `launchType: AgentLaunchType`
- `launchExecutablePath: String?`
- `launchCommand: String?`
- `launchArgs: [String]`

Recommended launch modes:

- `.executable`
- `.shellCommand`

Registry mapping:

- Registry `binary` entry:
  - `launchType = .executable`
  - `launchExecutablePath = extracted absolute path`
  - `launchArgs = binaryTarget.args ?? []`
- Registry `npx` entry:
  - `launchType = .shellCommand`
  - `launchCommand = "npx"`
  - `launchArgs = [package] + args`
- Registry `uvx` entry:
  - `launchType = .shellCommand`
  - `launchCommand = "uvx"`
  - `launchArgs = [package] + args`

Runtime change:

- Update Aizen's agent launch path so shell commands are spawned via `/usr/bin/env <command> ...`
- Keep direct executable launch for custom and binary-registry agents

This is the cleanest long-term model and matches your requirement to do the full refactor now instead of keeping the old executable-only assumption.

### 3. Separate registry-provided environment from user overrides

Registry distributions may include default environment variables.

Current `environmentVariables` in `AgentMetadata` are user-editable overrides. They should not be overloaded to store registry defaults.

Add a second environment layer:

- `baseEnvironment: [String: String]`

Merge order at launch time:

1. shell environment
2. registry/base environment
3. user environment overrides

This keeps registry-required flags like `DROID_DISABLE_AUTO_UPDATE=true` intact while still letting users override them deliberately.

### 4. Add a registry catalog service

Add a new actor in `Services/Agent/`, for example:

- `ACPRegistryService`

Responsibilities:

- Own `RegistryClient`
- Fetch and cache the registry
- Expose filtered agents for the current platform
- Refresh on user demand
- Cache downloaded registry icons

This service should be the only place that knows about `ACPRegistry` types outside the import flow.

### 4a. Add an icon cache for registry agents

Registry icons should be used when available and cached locally.

Add a small icon cache service, for example:

- `RegistryAgentIconCache`

Responsibilities:

- Download `iconURL` images from the registry
- Store them under Aizen-managed cache storage
- Return cached image data for Settings and chat UI
- Fall back to a generic icon when download fails

Recommended storage:

- `~/Library/Caches/com.aizen.app/agent-registry-icons/`

`AgentIconType` should support a cached registry image payload or a registry icon reference that resolves through the cache.

### 5. Initial seeding and import flow in Settings

On a fresh install, Aizen should automatically create three registry-backed agent entries:

- Claude Code
- Codex
- OpenCode

Recommended registry mapping:

- `claude-acp` -> display name `Claude Code`
- `codex-acp` -> display name `Codex`
- `opencode` -> display name `OpenCode`

These should behave like normal registry agents, not like a special built-in code path.

The remaining registry agents are discoverable through the picker.

Add a new Settings sheet, for example:

- `RegistryAgentPickerView`

Behavior:

- Opens from `Add From Registry`
- Shows searchable list of registry agents
- Shows:
  - name
  - description
  - current registry version
  - distribution badges (`binary`, `npx`, `uvx`)
  - repository link when available
- Filters out unsupported platform entries
- Marks already-added entries

Primary action:

- `Add`

What `Add` does:

- Create a new `AgentMetadata` entry with `source = .registry`
- Populate normalized launch data and base environment
- Persist registry reference fields
- Add the agent to the Settings sidebar immediately

### 6. Install behavior by distribution type

#### Binary registry agents

- After adding, the agent exists in Settings but is not yet valid until the binary is downloaded.
- `AgentDetailView` should show `Install` for registry-binary agents when they are not installed yet.
- Install should use either:
  - a small adapter around `ACPRegistry.AgentInstaller`, or
  - Aizen's existing binary installer if we map the registry entry into equivalent Aizen install metadata

Final behavior:

- Use `ACPRegistry.AgentInstaller` for binary extraction
- Persist the resulting launch descriptor and base environment
- Store extracted binaries under Aizen's existing managed directory:
  - `~/.aizen/agents/<agent-id>/...`

Do not use ACPRegistry's default Application Support install directory.

#### NPX / UVX registry agents

- No explicit install step is required in Aizen.
- After adding, the agent is immediately launchable through the new shell-command launch model.
- Validation should verify:
  - `/usr/bin/env` exists
  - the command (`npx` / `uvx`) is resolvable in the shell environment

## Required UI Changes

### Settings sidebar

In the `Agents` section:

1. existing agent entries
2. `Add From Registry`
3. `Add Custom Agent`

### Agent detail view

Replace built-in-only install logic with source-aware logic.

Rules:

- `Install` is shown for registry binary agents that are not installed yet
- `Edit Path` is shown only for:
  - custom agents
- `Edit` is shown only for:
  - custom agents
- `Delete` / `Remove` is shown for:
  - custom agents
  - registry agents
- Registry agents should also show:
  - source badge (`Registry`)
  - registry version
  - repository link if available

### Suggested picker UX

- Search field at top
- Manual refresh button
- Loading state
- Error state with retry
- Row action:
  - `Add` when not present
  - `Added` when already imported

### Chat empty state

The chat empty state currently shows one tile per enabled agent.

Update that surface so the agent tile row/grid includes an additional `+` tile:

- visually matches the existing agent tiles
- uses the same size, corner radius, border, and background treatment
- appears alongside the seeded/default agent tiles
- opens the registry sheet when clicked

Recommended placement:

- append the `+` tile after the visible agent tiles in the empty-state row/grid

This gives users a direct install path from the place where they first pick an agent to start a session.

## Data Model Changes

Recommended additions to `AgentMetadata`:

- `source: AgentSource`
- `launchType: AgentLaunchType`
- `launchExecutablePath: String?`
- `launchCommand: String?`
- `baseEnvironment: [String: String]`
- `registryId: String?`
- `registryVersion: String?`
- `registryRepositoryURL: String?`
- `registryIconURL: String?`
- `registryDistributionType: RegistryDistributionType?`

Recommended enums:

- `AgentSource`
  - `.custom`
  - `.registry`
- `RegistryDistributionType`
  - `.binary`
  - `.npx`
  - `.uvx`
- `AgentLaunchType`
  - `.executable`
  - `.shellCommand`

## Cutover Rules

This is a hard cutover, not a compatibility rollout.

Startup behavior after the refactor ships:

- automatically seed only:
  - Claude Code
  - Codex
  - OpenCode
- all other agents must be explicitly added through `Add From Registry`
- Aizen must not silently auto-add additional registry agents
- legacy built-in agent records should be discarded
- custom agents should remain intact

## Behavior Changes Needed In Existing Code

### Validation

Current validation is too strict for registry command launches.

Update validation so it can handle:

- direct executable launches
- shell-command launches

Validation rules:

- `.executable`
  - file exists
  - executable bit is present
- `.shellCommand`
  - command name is non-empty
  - command is discoverable through the shell environment, for example via `which`

### Install/update gating

Current install button logic branches on `metadata.isBuiltIn`.

That must change to source-aware logic based on:

- whether the agent is installable
- whether its selected distribution requires a download step

### Update detection

Do not reuse the current npm/PyPI/GitHub updater logic as the only source of truth for registry agents.

For registry agents, update availability should come from the registry:

- compare saved `registryVersion` with the latest fetched entry
- if changed:
  - binary agents offer `Update` to redownload
  - npx/uvx agents offer `Update` to refresh stored package/version/args/env metadata

## Acceptance Criteria

- Built-in agents no longer exist as a separate initialization path.
- A fresh install starts with exactly three registry-backed agents:
  - Claude Code
  - Codex
  - OpenCode
- Settings shows `Add From Registry` before `Add Custom Agent`.
- A user can search the official ACP registry from Settings.
- Adding a registry agent creates a persistent entry in Aizen's agent list.
- Registry icon URLs are downloaded, cached, and shown in the Settings picker and agent list when available.
- A binary registry agent can be added, installed, validated, and launched.
- An `npx` registry agent can be added, validated, and launched.
- A `uvx` registry agent can be added, validated, and launched.
- Binary registry agents install under `~/.aizen/agents`, consistent with existing managed agents.
- Registry-provided environment variables are preserved during launch.
- User environment overrides still work on top of registry defaults.
- Registry agents can be removed from Settings without affecting custom agents.
- Old built-in agent state is no longer part of the supported runtime model.
- A registry version change surfaces an `Update` action in the agent detail UI.

## Delivery Shape

Implement this as one cohesive change, not phased rollout.

Required pieces ship together:

1. Link the `ACPRegistry` product from `swift-acp` into the app target.
2. Refactor `AgentMetadata` to support `source`, launch descriptors, registry metadata, and base environment.
3. Remove built-in initialization and replace the managed-agent installer path with registry-backed installation.
4. Refactor launch and validation paths to support both executable and shell-command agents.
5. Add `ACPRegistryService`, icon caching, seeded default agents, and the Settings picker sheet.
6. Update Settings and agent detail UI to support registry agents end-to-end.
7. Add install, update, and remove behavior for registry agents.

## Final UX Decision

`Add` should immediately create and enable the registry agent in Settings for all distribution types.

Only the seeded default set is present automatically.

For any other agent:

- the user must install it from the registry
- UI surfaces that reference unavailable agents should direct the user to `Add From Registry`
- Aizen should prefer a clear CTA such as `Install From Registry` over showing missing-agent errors without guidance
- In the chat empty state, that CTA is the `+` tile rendered next to the agent tiles

Behavior after add:

- binary agents:
  - appear in the sidebar immediately
  - show as not yet installed until the user runs `Install`
- `npx` / `uvx` agents:
  - appear in the sidebar immediately
  - are considered launchable immediately
  - still show validation state if the required command is missing from the environment
