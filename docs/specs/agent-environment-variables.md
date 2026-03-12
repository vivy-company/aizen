# Agent Environment Variables Spec

## Goal

Allow users to define custom environment variables for any agent from Settings, and for custom agents while creating or editing them. Sensitive values must be stored in Keychain instead of `UserDefaults`. Those variables must be applied whenever Aizen launches the agent process, including ACP validation paths.

## Scope

- Built-in agents: editable from Settings.
- Custom agents: editable from Settings and in the create/edit form.
- Runtime: variables are merged into the launched agent process environment.
- Validation: the same variables are used when testing or validating an ACP executable.

## Data Model

- Extend `AgentMetadata` with `environmentVariables: [AgentEnvironmentVariable]`.
- Store each entry as:
  - `id: UUID`
  - `name: String`
  - `value: String`
  - `isSecret: Bool`
- Persist non-secret values in the existing `agentMetadataStore` UserDefaults payload.
- Persist secret values in Keychain using a stable key derived from `agentId + variableId`.
- Add backward-compatible decoding so existing saved agents without the new fields still load.

## Runtime Behavior

- Hydrate secret rows from Keychain before editing or launching.
- Convert hydrated rows into a launch dictionary right before process launch.
- Merge those values on top of the shell environment already used by the ACP client.
- Ignore rows with an empty variable name.
- If duplicate names exist, later rows win.
- Empty values are allowed and must be passed through as empty-string environment values.

## UI

- Add a reusable table-based env-vars editor used by:
  - `AgentDetailView`
  - `CustomAgentFormView`
- Editor behavior:
  - Add/remove rows.
  - Edit variable name and value inline in columns.
  - Toggle whether a row is stored securely.
  - Reveal or hide secure values while editing.
  - Show guidance that variables are merged on top of the shell environment.
  - Warn when rows are ignored because the name is empty.
  - Warn when duplicate names exist and clarify that the last value wins.

## Validation Paths

- `CustomAgentFormView.validateExecutablePath()` must launch the temp ACP client with the configured env vars.
- Settings “Test Connection” actions must use the configured env vars too.
- Validation must receive hydrated secret values, not the sanitized metadata payload.

## Acceptance Criteria

- Existing agents continue loading after upgrade.
- A built-in agent can be given an API key in Settings and use it in a new session.
- A custom agent can be created with env vars in the creation sheet.
- Editing env vars in Settings persists across relaunches.
- Secret rows are not stored in plaintext in `agentMetadataStore`.
- ACP validation and real launches behave consistently with the configured env vars.
