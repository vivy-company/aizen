# Pro Feature Gating Spec

## Summary

Introduce real product differentiation for the existing `Pro` and `Lifetime` licenses without changing the current
license system, billing backend, or activation flow.

The immediate goal is to make paid access mean something concrete in the app. The free experience should remain a
complete and useful local developer tool, but `Pro` should unlock broader scale and deeper hosted/integration
workflow.

This spec defines a first paid boundary based on:

- `1 workspace` for free, unlimited workspaces for `Pro` and `Lifetime`
- `1 custom agent` for free, unlimited custom agents for `Pro` and `Lifetime`
- GitHub and GitLab PR / workflow / CI surfaces as `Pro` and `Lifetime` features

This spec intentionally does not change:

- license activation
- billing portal
- plan types
- MCP as a core feature
- worktrees as a core feature
- local review as a core feature

This revision updates the implementation shape to match the current feature-first architecture. New work should land
under `Features/Workspace`, `Features/Settings`, and `Features/Worktree`, not legacy top-level `Services/*` or
`Views/*` buckets.

## Problem Statement

Aizen already has a working license system and checkout flow, but the product currently does not give paid users
meaningful in-app advantages.

Current public messaging frames `Aizen Pro` mostly as support for development plus future extras:

- [en.json](/Users/uyakauleu/development/aizen/web/src/i18n/translations/en.json#L84)
- [AizenProSettingsView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Settings/UI/AizenProSettingsView.swift)

That creates three problems:

- the upgrade path is vague
- the app cannot clearly communicate why a user should pay
- the current pricing feels disconnected from actual product access

The fix is not a new billing model. The fix is a product entitlement model layered on top of the existing license
state.

## Product Direction

The free product should be:

- one serious personal/local setup
- strong enough for individual evaluation and day-to-day use
- not artificially crippled in core mechanics

The paid product should be:

- broader in scope
- deeper in Git hosting integration
- clearly aimed at users managing multiple environments or more advanced setups

This leads to a simple positioning line:

- Free: one local Aizen environment
- Pro / Lifetime: unlimited environments and full Git hosting workflow

## Goals

- Keep the existing license system intact.
- Introduce concrete, understandable feature gates.
- Keep Aizen's local core useful in the free tier.
- Avoid gating MCP, worktrees, terminal, file browser, browser, or local review.
- Make `Pro` and `Lifetime` equivalent in entitlement level.
- Centralize feature checks so gates are consistent across service and UI layers.
- Fit the implementation to the current feature-first architecture.
- Update in-app and website copy so paid value is concrete.

## Non-Goals

- Changing Stripe products or introducing new plan types
- Splitting `Pro` and `Lifetime` into different feature sets
- Introducing hosted/cloud-only infrastructure
- Limiting worktrees
- Limiting MCP
- Limiting basic agent chat or parallel local agent usage
- Reworking local review into a paid feature

## Paid Boundary

### Free

- `1` workspace total
- built-in and registry agents remain available
- `1` custom agent
- worktrees
- MCP
- terminal
- file browser
- browser
- local review and diff workflows
- normal local agent sessions

### Pro and Lifetime

- unlimited workspaces
- unlimited custom agents
- pull request surfaces
- workflow / CI surfaces
- workflow logs and structured logs
- workflow actions such as rerun / trigger where supported

## Why These Features

### 1. Workspace count is the strongest non-destructive scale gate

A workspace is a natural product unit in Aizen. Limiting workspaces does not damage the core worktree-based workflow
inside a project, but it does create a meaningful upgrade path for users managing multiple projects, teams, or
contexts.

Current mutation boundary:

- [WorkspaceRepositoryStore+Workspace.swift](/Users/uyakauleu/development/aizen/aizen/Features/Workspace/Application/WorkspaceRepositoryStore+Workspace.swift)

Current entry points:

- [WorkspaceCreateSheet.swift](/Users/uyakauleu/development/aizen/aizen/Features/Workspace/UI/WorkspaceCreateSheet.swift)
- [WorkspaceSwitcherSheet.swift](/Users/uyakauleu/development/aizen/aizen/Features/Workspace/UI/WorkspaceSwitcherSheet.swift)
- [WorkspaceSidebarView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Workspace/UI/WorkspaceSidebarView.swift)

### 2. Custom agents are clearly an advanced feature

Giving one custom agent for free allows users to validate the capability. Unlimited custom agents creates a credible
power-user and workflow-builder upgrade.

Current mutation boundary:

- [AgentRegistry+Mutations.swift](/Users/uyakauleu/development/aizen/aizen/Features/Settings/Application/Agents/AgentRegistry+Mutations.swift)

Current entry points:

- [CustomAgentFormView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Settings/UI/Components/CustomAgentFormView.swift)
- [SettingsView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Settings/UI/SettingsView.swift)

### 3. PR / workflow / CI is a strong premium boundary

Git hosting integrations are deep, professional features. They are valuable, clearly differentiated, and not required
for Aizen's local core experience.

Current surfaces:

- [PullRequestsView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/Components/Git/PullRequests/PullRequestsView.swift)
- [WorkflowSidebarView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/Components/Git/Workflow/WorkflowSidebarView.swift)

Current runtime and service owners:

- [WorktreeRuntime.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/Application/WorktreeRuntime.swift)
- [WorkflowService.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/Application/Workflow/WorkflowService.swift)

## Features Explicitly Left Free

The following remain free because they are core to Aizen's identity or too central to degrade safely:

- worktrees
- MCP
- terminal
- file browser
- browser
- built-in agents
- local review comments and diff
- basic agent usage

This is intentional. The app should not become worse at its core job in order to manufacture upgrades.

## Entitlement Model

Introduce a small normalized entitlement layer under the Settings feature that translates license state into product
capabilities.

Suggested shape:

- `aizen/Features/Settings/Domain/License/AizenFeature.swift`
- `aizen/Features/Settings/Domain/License/AizenLimits.swift`
- `aizen/Features/Settings/Domain/License/FeatureGateError.swift`
- `aizen/Features/Settings/Application/License/FeatureEntitlementStore.swift`

Suggested types:

- `AizenEntitlementTier` with `.free` and `.paid`
- `AizenFeature` enum for paid-scoped capabilities
- `AizenLimits` struct with `maxWorkspaces` and `maxCustomAgents`
- `FeatureEntitlementSnapshot` that exposes tier, limits, and helper checks
- `FeatureGateError` for shared service-layer denial handling

Suggested capabilities:

- `canCreateAdditionalWorkspace(currentCount:)`
- `canCreateAdditionalCustomAgent(currentCount:)`
- `canAccessPullRequests`
- `canAccessWorkflowRuns`
- `canAccessWorkflowLogs`
- `canTriggerWorkflowActions`

Suggested limits:

- `maxWorkspaces`
- `maxCustomAgents`

### Canonical license-state mapping

The entitlement layer must normalize the current licensing model instead of forcing each feature to interpret raw
license data itself.

Source of truth:

- [LicenseStateStore.swift](/Users/uyakauleu/development/aizen/aizen/Features/Settings/Application/License/LicenseStateStore.swift)
- [LicenseClient.swift](/Users/uyakauleu/development/aizen/aizen/Features/Settings/Infrastructure/License/LicenseClient.swift)

Mapping rules for v1:

- `.active` plus paid plan type maps to `.paid`
- `.offlineGrace` plus last known paid plan type maps to `.paid`
- `.checking` preserves the last resolved entitlement snapshot and must not temporarily downgrade the UI while
  validation is in flight
- `.unlicensed`, `.expired`, `.invalid`, and `.error` map to `.free`
- unknown backend `type` or `status` strings map to `.free` until explicitly supported
- `Pro` and `Lifetime` are equivalent and both map to `.paid`

For the first implementation:

- free tier: `maxWorkspaces = 1`, `maxCustomAgents = 1`
- paid tier: unlimited for both

No service or view should directly invent its own interpretation of `licenseType`, `licenseStatus`, or
`LicenseStateStore.Status`.

## Enforcement Rules

### Shared enforcement contract

The central rule is:

- UI checks are for product packaging and discoverability
- service and runtime checks are the real enforcement boundary

Required behavior:

- every denied mutation or paid-only action path must fail through a shared `FeatureGateError`
- UI should translate `FeatureGateError` into upgrade messaging and route the user to `Settings > Aizen Pro`
- grandfathering applies only to existing objects, never to creation of new paid-scoped objects
- editing and deleting existing objects remain allowed unless a feature is explicitly paid-only

### Workspace limit

The workspace limit must be enforced in both the application store and the UI.

Service enforcement:

- prevent creation of a second workspace in
  [WorkspaceRepositoryStore+Workspace.swift](/Users/uyakauleu/development/aizen/aizen/Features/Workspace/Application/WorkspaceRepositoryStore+Workspace.swift)
- compute the current count from the store or Core Data fetches, not from view-local state
- throw `FeatureGateError.limitReached(.additionalWorkspace, current: max:)` when the free limit is exceeded

UI enforcement:

- keep workspace creation entry points visible in
  [WorkspaceSwitcherSheet.swift](/Users/uyakauleu/development/aizen/aizen/Features/Workspace/UI/WorkspaceSwitcherSheet.swift),
  [WorkspaceCreateSheet.swift](/Users/uyakauleu/development/aizen/aizen/Features/Workspace/UI/WorkspaceCreateSheet.swift),
  and [WorkspaceSidebarView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Workspace/UI/WorkspaceSidebarView.swift)
- when the user is at the free limit, intercept the create flow with upgrade UI instead of silently doing nothing
- if the create sheet is already open, show an inline locked banner and disable the final create action

Behavior rules:

- existing users who already have more than one workspace before gating ships keep access to existing workspaces
- they cannot create additional workspaces unless licensed
- deleting a workspace and falling below the free limit re-enables free-tier creation
- the app must never hide or delete existing user data

### Custom agent limit

The custom-agent limit must be enforced in both the settings application layer and the UI.

Service enforcement:

- prevent creation of a second custom agent in
  [AgentRegistry+Mutations.swift](/Users/uyakauleu/development/aizen/aizen/Features/Settings/Application/Agents/AgentRegistry+Mutations.swift)
- count only `.custom` agents toward the limit
- built-in and registry agents do not count toward the free-tier cap
- fail through `FeatureGateError.limitReached(.additionalCustomAgent, current: max:)`

UI enforcement:

- keep the add-custom-agent route visible in
  [SettingsView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Settings/UI/SettingsView.swift) and
  [CustomAgentFormView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Settings/UI/Components/CustomAgentFormView.swift)
- when the user is at the free limit, intercept the add flow and route to `Settings > Aizen Pro`
- if the form is already open, show an inline locked banner and disable the final save action

Behavior rules:

- existing users who already have more than one custom agent keep those agents
- they cannot add more unless licensed
- editing and deleting existing custom agents stays allowed
- removing a custom agent and falling below the free limit re-opens the free slot

### Pull request surfaces

PR surfaces are paid-only for the first implementation and must be gated before any PR loading starts.

Gated surfaces:

- [PullRequestsView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/Components/Git/PullRequests/PullRequestsView.swift)

Required enforcement:

- the view must not call `configure(repoPath:)` or `loadPullRequests()` when the user is not entitled
- the view model must also reject direct action or load calls with `FeatureGateError.featureLocked(.pullRequests)`
- the app must not start hosted metadata fetches, list loading, detail loading, merge, close, approve, request
  changes, or comment actions while locked

Behavior rules:

- when the user opens the PR area without entitlement, show a clear locked state instead of loading PR data
- the locked state should explain that Git hosting integrations are part of `Aizen Pro`
- a pure view-only gate is not sufficient; the underlying action and load paths must also be protected

### Workflow / CI surfaces

Workflow surfaces are also paid-only for the first implementation and must be gated at both runtime activation and
service action boundaries.

Gated surfaces:

- [WorkflowSidebarView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/UI/Components/Git/Workflow/WorkflowSidebarView.swift)
- [WorkflowService.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/Application/Workflow/WorkflowService.swift)
- [WorktreeRuntime.swift](/Users/uyakauleu/development/aizen/aizen/Features/Worktree/Application/WorktreeRuntime.swift)

Required enforcement:

- `WorktreeRuntime` must gate workflow activation before calling `workflowService.configure`, enabling auto-refresh,
  or restoring workflow-related state
- `WorkflowService` must reject refresh, logs, polling, rerun, and trigger actions when the user is not entitled
- the workflow UI should render a locked state before CLI/provider/auth errors, because lack of entitlement is the
  primary reason the surface is unavailable

Behavior rules:

- when the user opens the workflow area without entitlement, show a locked state instead of loading workflow data
- workflow refresh, logs, polling, and action paths must not start unless entitled
- the app should not show half-initialized workflow state for locked users

## UX Rules

Do not make gated features disappear silently.

Use soft walls with one consistent pattern:

- keep navigation and entry points visible when reasonable
- for resource-creation limits, intercept the action and explain the upgrade path
- for paid-only hosted surfaces, open into a locked state instead of a broken or partially loaded state
- if a creation form is already open, show an inline locked banner and disable the final submit action
- route upgrade actions into the existing `Aizen Pro` settings flow
- use the same reason strings and upgrade copy emitted by the entitlement layer

This should feel like product packaging, not punishment.

## Copy Direction

The app and website should stop describing paid access as vague support plus future extras.

Replace that message with concrete plan language.

Suggested free copy:

- `Free includes 1 workspace, built-in agents, MCP, worktrees, terminal, browser, files, and local review.`

Suggested paid copy:

- `Pro unlocks unlimited workspaces, unlimited custom agents, and GitHub / GitLab PR and CI workflows.`

Existing pricing UI that currently needs copy updates:

- [AizenProSettingsView.swift](/Users/uyakauleu/development/aizen/aizen/Features/Settings/UI/AizenProSettingsView.swift)
- [en.json](/Users/uyakauleu/development/aizen/web/src/i18n/translations/en.json#L84)

## Data and State-Change Rules

No data migration is required for license data.

The feature-gating rollout must preserve:

- existing workspaces
- existing custom agents
- existing license activations

Grandfathering rules:

- users over the new free limits keep access to what they already created
- they only hit the gate when attempting to create additional paid-scoped resources

Live state-change rules:

- upgrading to a paid plan while the app is open should unlock paid surfaces without requiring a restart
- downgrading or losing paid entitlement should stop new paid-only writes and hosted actions immediately
- downgrading must not remove or hide grandfathered workspaces or custom agents
- workflow auto-refresh and polling should stop when entitlement is lost

This avoids destructive behavior and reduces support burden.

## Implementation Shape

### 1. Add a centralized entitlement layer inside the Settings feature

Suggested locations:

- `aizen/Features/Settings/Domain/License/`
- `aizen/Features/Settings/Application/License/FeatureEntitlementStore.swift`

Responsibilities:

- observe or query `LicenseStateStore`
- normalize backend `type` and `status` strings into one internal entitlement snapshot
- expose feature booleans, numeric limits, and denial helpers
- expose stable upgrade reasons and messaging for UI

### 2. Add counting/query helpers at the real ownership boundaries

Needed helpers:

- current workspace count from the Workspace feature store
- current custom-agent count from the Settings feature registry/store

These should be resolved from current stores, not duplicated in views.

### 3. Enforce limits at mutation boundaries

Service-level enforcement is mandatory for:

- workspace creation in the Workspace feature store
- custom-agent creation in the Settings feature registry

This protects against missed UI entry points.

### 4. Gate hosted surfaces at runtime and service boundaries

Required owners:

- PR surface gate in the PR view and PR view model
- workflow activation gate in `WorktreeRuntime`
- workflow load and action guards in `WorkflowService`

The goal is to stop network work, polling, and paid-only actions before they start.

### 5. Add locked-state components in the Worktree UI

Suggested locations:

- near `PullRequestsView`
- near `WorkflowSidebarView`

The locked state should include:

- concise value statement
- upgrade CTA
- route to `Settings > Aizen Pro`

### 6. Update plan and pricing copy

The product language should consistently reflect the real gates.

### 7. Add automated coverage for entitlement mapping and gating behavior

Coverage should include:

- license-state normalization
- workspace and custom-agent limits
- grandfathering behavior
- live upgrade and downgrade while the app is open
- offline-grace behavior
- locked PR and workflow surfaces not starting background work

## Acceptance Criteria

- `LicenseStateStore.Status.active` and `.offlineGrace` with paid plan types resolve to paid entitlements.
- `LicenseStateStore.Status.checking` preserves the last resolved entitlement snapshot and does not flicker the UI.
- `LicenseStateStore.Status.unlicensed`, `.expired`, `.invalid`, and `.error` resolve to free entitlements.
- Unknown backend `type` or `status` values do not accidentally grant paid access.
- Unlicensed users can use exactly one workspace and are blocked from creating a second.
- Licensed `Pro` and `Lifetime` users can create unlimited workspaces.
- Unlicensed users can create exactly one custom agent and are blocked from creating a second.
- Built-in and registry agents do not count toward the custom-agent limit.
- Licensed `Pro` and `Lifetime` users can create unlimited custom agents.
- Unlicensed users see locked states for PR and workflow / CI surfaces instead of partial broken behavior.
- Unlicensed users opening PR and workflow surfaces do not start hosted loading, workflow polling, logs, or action paths.
- Licensed `Pro` and `Lifetime` users retain full access to PR and workflow / CI surfaces.
- Worktrees remain free.
- MCP remains free.
- Local review remains free.
- Existing users above new free limits keep access to existing objects and are only blocked on new creation.
- Upgrading or downgrading while the app is open updates gating behavior without requiring restart.
- Pricing and upgrade copy describe the actual feature set rather than vague future benefits.

## Open Questions

- Should locked PR and workflow states use provider-neutral copy in v1, or provider-specific GitHub / GitLab copy after
  provider detection?
- Should upgrade interception route directly to `Settings > Aizen Pro`, or present a dedicated paywall sheet that then
  links into settings?
- Do we want to capture entitlement gate hits in analytics, or keep this first rollout behavior-only?

## Recommendation

Ship the first paid boundary exactly as defined in this spec:

- `1` workspace free
- `1` custom agent free
- PR / workflow / CI as paid
- keep MCP, worktrees, and local review free

This is the cleanest first monetization step that creates real product value without undermining Aizen's local core.
