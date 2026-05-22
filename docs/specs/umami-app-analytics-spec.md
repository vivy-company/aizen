# Umami App Analytics Spec

## Summary

Add privacy-conscious product analytics to the Aizen macOS app using the existing Umami instance and the
`wiedymi/swift-umami` Swift package.

The goal is approximate product visibility:

- how many people open and actively use the app
- which high-level surfaces are used
- which agent providers and integration categories are used
- which versions and channels are active
- whether updates are being adopted

This is not a behavioral recording system, debug-log pipeline, crash reporter, or repository-content telemetry system.

## Product Decision

Use the same Umami website for the marketing website and the macOS app.

Website and app analytics use:

- `https://analytics.vivy.app/script.js`
- website ID `52cc0341-4315-4223-98f7-d948226dcc54`
- [BaseLayout.astro](/Users/uyakauleu/development/aizen/web/src/layouts/BaseLayout.astro)

The app uses stable synthetic paths such as `/app`, `/worktree`, and `/agent-session` so app events remain separable
from website pageviews inside the same Umami property.

Use the website ID through build configuration or an app configuration constant. Do not hardcode the website ID deep
inside feature code.

## Goals

- Track approximate daily active app usage.
- Track coarse feature adoption without collecting project content.
- Track version, channel, and platform distribution.
- Keep analytics enabled by default, with a visible setting to disable it.
- Keep the event layer small, typed, and easy to audit.
- Route app code through an internal analytics facade rather than calling Umami directly from features.

## Non-Goals

- Session replay
- Per-screen navigation analytics for every SwiftUI view
- Capturing prompts, responses, terminal commands, file paths, repository names, remote URLs, branch names, commit
  messages, or chat content
- Tracking individual people across devices
- Replacing Sparkle request logs for download/update counts
- Building an analytics dashboard in Aizen
- Sending analytics from tests or previews

## Privacy Boundary

Allowed global properties:

- `app_version`
- `build_number`
- `channel`: `stable`, `nightly`, `debug`
- `macos_major`
- `macos_minor`
- `arch`: `arm64`, `x86_64`, `unknown`
- `locale_language`
- `license_tier`: `free`, `pro`, `lifetime`, `unknown`
- `analytics_schema_version`

Allowed event-specific properties:

- small enums
- booleans
- counts
- durations rounded to coarse buckets
- error categories that do not include raw error messages

Forbidden properties:

- user name
- email address
- computer hostname
- local file paths
- repository names
- worktree names
- branch names
- remote URLs
- organization names
- terminal commands
- environment variable names or values
- agent prompts
- agent responses
- tool-call arguments
- file contents
- diff contents
- commit messages
- license key
- API keys or tokens

The Umami `hostname` field must be a constant such as `app.aizen.win`, not the user's Mac hostname.

## Identity Model

Generate one random anonymous install ID on first analytics use and store it locally.

Rules:

- UUID string is enough.
- Store in user defaults or a small app preferences store.
- Do not derive it from machine identifiers.
- Do not sync it through iCloud.
- Do not include license identity, email, or hardware identifiers.
- Use it as Umami's distinct `id` value so daily active usage can be approximated.

If the user disables analytics, stop sending events immediately. The local anonymous install ID may remain stored unless
we add a separate "Reset analytics identity" control later.

## Consent And Settings

Add a Settings control:

- label: `Share anonymous usage analytics`
- default: enabled
- supporting copy: `Helps improve Aizen by sending anonymous app usage counts. Project names, paths, prompts, terminal commands, and file contents are never sent.`

Requirements:

- The toggle must be checked before sending any event.
- The event client should be cheap to call even when disabled.
- The website privacy policy must be updated before enabling app analytics in public builds.

## Architecture

Add analytics as cross-feature infrastructure:

```text
aizen/
├── Integrations/
│   └── Analytics/
│       ├── AnalyticsClient.swift
│       ├── AnalyticsEvent.swift
│       ├── AnalyticsProperties.swift
│       ├── AnalyticsSettings.swift
│       └── UmamiAnalyticsClient.swift
└── Features/
    └── Settings/
        └── UI/
            └── PrivacySettingsView.swift
```

Use `Integrations/Analytics` because analytics receives events from many features and sends them to an external
service. It should not live inside one feature.

Feature code should call:

```swift
Analytics.shared.track(.agentSessionStarted(provider: .codex, entryPoint: .chat))
```

Feature code should not construct Umami payloads.

`UmamiAnalyticsClient` owns:

- `UmamiTrackerClient`
- base URL
- website ID shared with the web package
- User-Agent
- anonymous install ID
- global properties
- event batching if adopted later

`AnalyticsClient` should be actor-isolated or otherwise concurrency-safe. Public APIs should be fire-and-forget from
UI and application code.

## Dependency

Use the user's `wiedymi/swift-umami` package.

Until releases/tags exist, pin to a revision in the Xcode package dependency. Once a release tag exists, switch to a
version requirement.

The app should depend only on the public `Umami` product from feature integration code. All direct package usage should
remain inside `UmamiAnalyticsClient`.

## Event Naming

Use snake_case names.

Rules:

- event names describe completed user-visible actions or coarse lifecycle events
- no dynamic values in event names
- dynamic values belong in validated enum/count properties
- avoid one event per minor button click
- prefer stable names that can survive UI refactors

## Event URLs

Use synthetic Umami URLs to group app events:

```text
/app
/workspace
/repository
/worktree
/agent-session
/terminal
/browser
/files
/settings
/updates
/license
```

These are not real website URLs. They are app analytics paths.

## Initial Event Set

### App Lifecycle

#### `app_opened`

Send once per app process launch after startup completes.

URL: `/app`

Properties:

- global properties only

Purpose:

- rough launch count
- version/channel distribution

#### `app_active_daily`

Send at most once per local calendar day per install.

URL: `/app`

Properties:

- global properties only

Purpose:

- best Umami-based approximation of DAU
- less noisy than hourly Sparkle checks or repeated app activation

#### `app_became_active`

Optional. Send when the app becomes active, rate-limited to at most once per hour.

URL: `/app`

Properties:

- `activation_source`: `launch`, `dock`, `deeplink`, `unknown`

Purpose:

- understand whether Aizen is used briefly or repeatedly during a day

This event can be skipped in the first implementation if we want to keep volume lower.

### Workspace And Repository

#### `workspace_created`

Send after a workspace is successfully created.

URL: `/workspace`

Properties:

- `workspace_count_bucket`: `1`, `2_3`, `4_10`, `11_plus`

Forbidden:

- workspace name
- workspace path

#### `repository_added`

Send after a repository is successfully added to a workspace.

URL: `/repository`

Properties:

- `source`: `local`, `clone`, `unknown`
- `provider`: `github`, `gitlab`, `other`, `unknown`
- `repository_count_bucket`: `1`, `2_3`, `4_10`, `11_plus`

Forbidden:

- repository name
- repository path
- remote URL
- organization name

#### `worktree_created`

Send after a worktree is successfully created.

URL: `/worktree`

Properties:

- `source`: `new_branch`, `existing_branch`, `unknown`
- `worktree_count_bucket`: `1`, `2_3`, `4_10`, `11_plus`

Forbidden:

- branch name
- worktree name
- path

#### `worktree_opened`

Send when the user opens/selects a worktree, rate-limited per worktree session.

URL: `/worktree`

Properties:

- `has_chat_session`: boolean
- `has_terminal_session`: boolean
- `has_browser_session`: boolean

Forbidden:

- worktree identity
- repository identity

### Agent And Chat

#### `agent_session_started`

Send when a new agent session is successfully started.

URL: `/agent-session`

Properties:

- `provider`: `codex`, `claude`, `gemini`, `custom`, `unknown`
- `entry_point`: `chat`, `review`, `command_palette`, `unknown`
- `has_attachments`: boolean
- `model_family`: coarse enum if known and safe, otherwise omit

Forbidden:

- prompt text
- model ID if it includes user-custom names or private endpoint data
- project files
- selected file paths

#### `agent_message_sent`

Send when a user sends a chat message, rate-limited only by actual sends.

URL: `/agent-session`

Properties:

- `provider`: `codex`, `claude`, `gemini`, `custom`, `unknown`
- `has_attachments`: boolean
- `attachment_count_bucket`: `0`, `1`, `2_5`, `6_plus`

Forbidden:

- message text
- attachment names
- attachment paths
- attachment contents

#### `agent_tool_call_completed`

Optional phase-two event. Send when a tool call finishes.

URL: `/agent-session`

Properties:

- `tool_category`: `filesystem`, `terminal`, `browser`, `git`, `network`, `unknown`
- `result`: `success`, `denied`, `failed`

Forbidden:

- tool name if it may contain user-defined server/tool names
- tool arguments
- command text
- file paths

First implementation can skip this event because it has higher privacy risk and higher volume.

### Terminal

#### `terminal_opened`

Send when a terminal pane/session is opened.

URL: `/terminal`

Properties:

- `entry_point`: `worktree`, `command_palette`, `unknown`
- `split_count_bucket`: `1`, `2`, `3_4`, `5_plus`

Forbidden:

- shell command
- current directory
- environment

#### `terminal_split_created`

Send when the user creates a terminal split.

URL: `/terminal`

Properties:

- `orientation`: `horizontal`, `vertical`, `unknown`
- `split_count_bucket`: `2`, `3_4`, `5_plus`

### Browser

#### `browser_opened`

Send when the built-in browser surface opens.

URL: `/browser`

Properties:

- `entry_point`: `worktree`, `command_palette`, `unknown`

Forbidden:

- current URL
- page title
- domain

#### `browser_tab_created`

Send when a browser tab is created.

URL: `/browser`

Properties:

- `tab_count_bucket`: `1`, `2_3`, `4_10`, `11_plus`

Forbidden:

- URL
- title
- domain

### Files

#### `file_browser_opened`

Send when the file browser surface opens.

URL: `/files`

Properties:

- `entry_point`: `worktree`, `command_palette`, `unknown`

Forbidden:

- selected path
- file name
- directory name

#### `file_opened`

Optional phase-two event. Send only as a coarse file-type signal.

URL: `/files`

Properties:

- `file_kind`: `source`, `markdown`, `image`, `config`, `unknown`

Forbidden:

- file name
- extension if we decide extension-level reporting is too identifying
- path
- contents

First implementation can skip this event.

### Settings

#### `settings_opened`

Send when Settings opens, rate-limited to at most once per app launch.

URL: `/settings`

Properties:

- global properties only

#### `custom_agent_created`

Send after a custom agent is created.

URL: `/settings`

Properties:

- `distribution`: `local_command`, `npm`, `github`, `binary`, `uv`, `unknown`
- `custom_agent_count_bucket`: `1`, `2_3`, `4_10`, `11_plus`

Forbidden:

- agent name
- command
- executable path
- environment variables

#### `mcp_server_added`

Send after an MCP server is added.

URL: `/settings`

Properties:

- `source`: `registry`, `manual`, `unknown`
- `server_count_bucket`: `1`, `2_3`, `4_10`, `11_plus`

Forbidden:

- server name if user-defined
- command
- URL
- environment variables

### License

#### `license_activated`

Send after successful license activation.

URL: `/license`

Properties:

- `license_tier`: `pro`, `lifetime`, `unknown`

Forbidden:

- license key
- email
- Stripe/customer identifiers

#### `upgrade_clicked`

Send when the user opens an upgrade flow from inside the app.

URL: `/license`

Properties:

- `source`: `settings`, `feature_gate`, `unknown`

### Updates

Sparkle and R2/Cloudflare logs remain the best source for update checks and download counts. Umami can still track
coarse in-app update actions.

#### `update_check_started`

Send when the user manually checks for updates.

URL: `/updates`

Properties:

- `source`: `settings`, `menu`, `unknown`

Do not send automatic hourly Sparkle checks to Umami.

#### `update_installed`

Send after an app version launches for the first time following an update, inferred locally by comparing the previous
seen build number to the current build number.

URL: `/updates`

Properties:

- `previous_version_known`: boolean
- `previous_channel`: `stable`, `nightly`, `unknown`

Do not send previous exact version in the first implementation unless needed.

## First Implementation Scope

Implement only these events first:

- `app_opened`
- `app_active_daily`
- `workspace_created`
- `repository_added`
- `worktree_created`
- `agent_session_started`
- `terminal_opened`
- `browser_opened`
- `file_browser_opened`
- `settings_opened`
- `custom_agent_created`
- `mcp_server_added`
- `license_activated`
- `upgrade_clicked`
- `update_check_started`
- `update_installed`

Defer these until the first data review:

- `app_became_active`
- `agent_message_sent`
- `agent_tool_call_completed`
- `terminal_split_created`
- `browser_tab_created`
- `file_opened`
- any duration tracking

## Rate Limiting And Deduplication

Required local dedupe keys:

- `last_app_active_daily_date`
- `last_settings_opened_build_or_launch_id`
- `last_update_installed_build`

Recommended event limits:

- `app_active_daily`: once per local day
- `settings_opened`: once per process launch
- surface opened events: once per surface/session creation, not every focus change
- update check events: manual checks only

No background queue is required for the first implementation. Failed analytics sends can be dropped.

## Dashboard Expectations

In Umami, read app analytics as:

- Visitors on `/app` + `app_active_daily`: approximate daily active installs
- Events by name: feature adoption
- Event data by `app_version` and `channel`: release health and adoption
- Events by `license_tier`: free vs paid usage mix
- Events by synthetic URL: surface-level usage

Do not use Umami event count alone as user count. Use distinct visitors/IDs where possible.

## Privacy Policy Update

Update website privacy copy before public rollout.

Required message:

- Aizen may send anonymous app usage counts if the user leaves analytics enabled.
- Analytics helps understand app usage and prioritize improvements.
- Analytics does not include project names, file paths, repository URLs, terminal commands, prompts, responses, file
  contents, or personal account information.
- Users can disable analytics in Settings.

## Testing

Unit tests:

- event payload builders reject or omit forbidden dynamic strings
- analytics disabled means no network send
- `app_active_daily` sends once per date
- `update_installed` sends once per build
- global properties are present

Manual tests:

- fresh installs show the analytics setting enabled
- builds without a configured Umami website ID do not send
- release build sends to website ID `52cc0341-4315-4223-98f7-d948226dcc54`
- disabling the setting stops events immediately
- Umami dashboard shows `app_active_daily` under `/app`
- no local project names, paths, prompts, commands, or URLs appear in event data

## Open Questions

- Should the app include a "Reset anonymous analytics identity" button?
- Should `agent_message_sent` be included in phase one, or is `agent_session_started` enough initially?
- Should Pro/free license tier be sent before the privacy-policy update, or deferred until after the first app analytics
  release?
