# Pro Feature Gating Spec

## Summary

Introduce real product differentiation for the existing `Pro` and `Lifetime` licenses without changing the current license system, billing backend, or activation flow.

The immediate goal is to make paid access mean something concrete in the app. The free experience should remain a complete and useful local developer tool, but `Pro` should unlock broader scale and deeper hosted/integration workflow.

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

## Problem Statement

Aizen already has a working license system and checkout flow, but the product currently does not give paid users meaningful in-app advantages.

Current public messaging frames `Aizen Pro` mostly as support for development plus future extras:

- [en.json](/Users/uyakauleu/development/aizen/web/src/i18n/translations/en.json#L84)
- [AizenProSettingsView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/AizenProSettingsView.swift#L347)

That creates three problems:

- the upgrade path is vague
- the app cannot clearly communicate why a user should pay
- the current pricing feels disconnected from actual product access

The fix is not a new billing model. The fix is a product entitlement model layered on top of the existing license state.

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
- Keep Aizen’s local core useful in the free tier.
- Avoid gating MCP, worktrees, terminal, file browser, browser, or local review.
- Make `Pro` and `Lifetime` equivalent in entitlement level.
- Centralize feature checks so gates are consistent across service and UI layers.
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

A workspace is a natural product unit in Aizen. Limiting workspaces does not damage the core worktree-based workflow inside a project, but it does create a meaningful upgrade path for users managing multiple projects, teams, or contexts.

Primary write path today:

- [RepositoryManager.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/RepositoryManager.swift#L56)

Primary creation UI today:

- [WorkspaceCreateSheet.swift](/Users/uyakauleu/development/aizen/aizen/Views/Workspace/WorkspaceCreateSheet.swift)
- [WorkspaceSwitcherSheet.swift](/Users/uyakauleu/development/aizen/aizen/Views/Workspace/WorkspaceSwitcherSheet.swift)

### 2. Custom agents are clearly an advanced feature

Giving one custom agent for free allows users to validate the capability. Unlimited custom agents creates a credible power-user and workflow-builder upgrade.

Primary write path today:

- [AgentRegistry.swift](/Users/uyakauleu/development/aizen/aizen/Services/Agent/AgentRegistry.swift#L60)

Primary creation UI today:

- [CustomAgentFormView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/Components/CustomAgentFormView.swift#L419)

### 3. PR / workflow / CI is a strong premium boundary

Git hosting integrations are deep, professional features. They are valuable, clearly differentiated, and not required for Aizen’s local core experience.

Primary surfaces today:

- [PullRequestsView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/PullRequests/PullRequestsView.swift#L10)
- [WorkflowSidebarView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/Workflow/WorkflowSidebarView.swift)
- [WorkflowService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Workflow/WorkflowService.swift#L12)

## Features Explicitly Left Free

The following remain free because they are core to Aizen’s identity or too central to degrade safely:

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

Introduce a small app-level entitlement layer that translates current license state into product capabilities.

Suggested shape:

- `FeatureEntitlementService`
- `AizenFeature` enum
- `AizenLimits` struct

Suggested capabilities:

- `canCreateAdditionalWorkspace`
- `canCreateAdditionalCustomAgent`
- `canAccessPullRequests`
- `canAccessWorkflowRuns`
- `canAccessWorkflowLogs`
- `canTriggerWorkflowActions`

Suggested limits:

- `maxWorkspaces`
- `maxCustomAgents`

For the first implementation:

- unlicensed users: `maxWorkspaces = 1`, `maxCustomAgents = 1`
- active `Pro` or `Lifetime`: unlimited for both

The entitlement layer should be derived from:

- [LicenseManager.swift](/Users/uyakauleu/development/aizen/aizen/Services/License/LicenseManager.swift)

No service or view should directly invent its own interpretation of license state.

## Enforcement Rules

### Workspace limit

The workspace limit must be enforced in both service and UI layers.

Service enforcement:

- prevent creation of a second workspace in [RepositoryManager.swift](/Users/uyakauleu/development/aizen/aizen/Services/Git/RepositoryManager.swift#L56)

UI enforcement:

- disable or intercept “new workspace” entry points
- show upgrade messaging in:
  - [WorkspaceSwitcherSheet.swift](/Users/uyakauleu/development/aizen/aizen/Views/Workspace/WorkspaceSwitcherSheet.swift)
  - [WorkspaceCreateSheet.swift](/Users/uyakauleu/development/aizen/aizen/Views/Workspace/WorkspaceCreateSheet.swift)
  - [WorkspaceSidebarView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Workspace/WorkspaceSidebarView.swift)

Behavior rule:

- existing users who already have more than one workspace before gating ships keep access to existing workspaces
- they cannot create additional workspaces unless licensed
- the app must never hide or delete existing user data

### Custom agent limit

The custom agent limit must be enforced in both registry/service and UI layers.

Service enforcement:

- prevent creation of a second custom agent in [AgentRegistry.swift](/Users/uyakauleu/development/aizen/aizen/Services/Agent/AgentRegistry.swift#L60)

UI enforcement:

- disable or intercept “add custom agent” flows in:
  - [CustomAgentFormView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/Components/CustomAgentFormView.swift#L419)
  - [SettingsView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/SettingsView.swift)

Behavior rule:

- existing users who already have more than one custom agent keep those agents
- they cannot add more unless licensed
- editing and deleting existing custom agents stays allowed

### Pull request surfaces

PR surfaces should be treated as paid-only for the first implementation.

Gated surfaces:

- [PullRequestsView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/PullRequests/PullRequestsView.swift#L10)

Behavior rule:

- when the user opens the PR area without entitlement, show a clear locked state instead of loading PR data
- the locked state should explain that Git hosting integrations are part of `Aizen Pro`

### Workflow / CI surfaces

Workflow surfaces should also be treated as paid-only for the first implementation.

Gated surfaces:

- [WorkflowSidebarView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Worktree/Components/Git/Workflow/WorkflowSidebarView.swift)
- [WorkflowService.swift](/Users/uyakauleu/development/aizen/aizen/Services/Workflow/WorkflowService.swift#L12)

Behavior rule:

- when the user opens the workflow area without entitlement, show a locked state instead of loading workflow data
- workflow refresh, logs, polling, and action paths should not start unless entitled

## UX Rules

Do not make gated features disappear silently.

Use soft walls:

- keep entry points visible when reasonable
- show locked states and upgrade explanation
- allow the user to understand what the feature does
- route upgrade actions into the existing `Aizen Pro` settings flow

This should feel like product packaging, not punishment.

## Copy Direction

The app and website should stop describing paid access as vague support plus future extras.

Replace that message with concrete plan language.

Suggested free copy:

- `Free includes 1 workspace, built-in agents, MCP, worktrees, terminal, browser, files, and local review.`

Suggested paid copy:

- `Pro unlocks unlimited workspaces, unlimited custom agents, and GitHub / GitLab PR and CI workflows.`

Existing pricing UI that currently needs copy updates:

- [AizenProSettingsView.swift](/Users/uyakauleu/development/aizen/aizen/Views/Settings/AizenProSettingsView.swift#L347)
- [en.json](/Users/uyakauleu/development/aizen/web/src/i18n/translations/en.json#L84)

## Data and Migration Rules

No data migration is required for license data.

The feature-gating rollout must preserve:

- existing workspaces
- existing custom agents
- existing license activations

Grandfathering rule:

- users over the new free limits keep access to what they already created
- they only hit the gate when attempting to create additional paid-scoped resources

This avoids destructive behavior and reduces support burden.

## Implementation Shape

### 1. Add centralized feature entitlement service

Suggested location:

- `aizen/Services/License/FeatureEntitlementService.swift`

Responsibilities:

- observe or query `LicenseManager`
- expose feature booleans and numeric limits
- expose upgrade reasons/messages for UI

### 2. Add counting/query helpers

Needed helpers:

- current workspace count
- current custom agent count

These should be resolved from current stores, not duplicated in views.

### 3. Enforce limits at mutation boundaries

Service-level enforcement is mandatory for:

- workspace creation
- custom agent creation

This protects against missed UI entry points.

### 4. Add locked-state views for PR and workflow surfaces

Suggested locations:

- near `PullRequestsView`
- near `WorkflowSidebarView`

The locked state should include:

- concise value statement
- upgrade CTA
- route to `Settings > Aizen Pro`

### 5. Update plan and pricing copy

The product language should consistently reflect the real gates.

## Acceptance Criteria

- Unlicensed users can use exactly one workspace and are blocked from creating a second.
- Licensed `Pro` and `Lifetime` users can create unlimited workspaces.
- Unlicensed users can create exactly one custom agent and are blocked from creating a second.
- Licensed `Pro` and `Lifetime` users can create unlimited custom agents.
- Unlicensed users see locked states for PR and workflow / CI surfaces instead of partial broken behavior.
- Licensed `Pro` and `Lifetime` users retain full access to PR and workflow / CI surfaces.
- Worktrees remain free.
- MCP remains free.
- Local review remains free.
- Existing users above new free limits keep access to existing objects and are only blocked on new creation.
- Pricing and upgrade copy describe the actual feature set rather than vague future benefits.

## Open Questions

- Should unlicensed users see a minimal PR / workflow teaser state, or should those surfaces be entirely locked?
- Should GitLab follow the exact same gate as GitHub in v1, or can rollout start with GitHub only?
- Should registry-added agents count separately from custom agents for any future packaging, even though they are free in this spec?

## Recommendation

Ship the first paid boundary exactly as defined in this spec:

- `1` workspace free
- `1` custom agent free
- PR / workflow / CI as paid
- keep MCP, worktrees, and local review free

This is the cleanest first monetization step that creates real product value without undermining Aizen’s local core.
