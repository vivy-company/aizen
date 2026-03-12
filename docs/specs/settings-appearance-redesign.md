# Settings Appearance Redesign Spec

## Goal

Clean up Settings by introducing a single `Appearance` section that owns visual styling across Aizen.

The main product decision is:

- Ghostty terminal themes become the single color/theme source for the app.
- Terminal theme drives app surfaces, terminal, editor, diff, chat, and markdown styling.
- Typography and spacing can still be configured separately for terminal, code, and markdown.

This spec is intentionally opinionated so we can discuss one concrete direction instead of a broad set of options.

## Why This Change

The current Settings structure splits appearance across three unrelated top-level pages:

- `Terminal`
- `Editor`
- `Chat`

That split no longer matches how the app behaves.

### Current problems

- The app surface already derives from the terminal theme through `AppSurfaceTheme`.
- Chat timeline markdown already derives many colors from the terminal theme.
- Editor themes are stored separately, but they still come from the same Ghostty theme catalog.
- `Chat` is currently an appearance-only page, not a behavior/settings page.
- `Terminal`, `Editor`, and `Chat` each expose fonts or theme controls independently, so users have to guess which one is the real source of truth.

### Current implementation drift

There is already evidence that the split model is creating bugs and dead settings:

- `AppSurfaceTheme` reads `usePerAppearanceTheme`, while terminal settings write `terminalUsePerAppearanceTheme`.
- `ChatSettings.blockSpacingKey` exists in Settings, but the markdown renderers currently use hardcoded spacing values instead of that setting.
- Many views read raw `@AppStorage` keys directly, so appearance rules are duplicated across the codebase instead of being resolved once.

The current structure is not just visually messy. It is producing inconsistent behavior.

## Product Direction

Add a new top-level `Appearance` settings page and make it the only place for theme, typography, and markdown presentation controls.

### Sidebar changes

Proposed top-level order:

- `General`
- `Appearance`
- `Transcription`
- `Git`
- `Terminal`
- `Editor`
- `Agents`
- `Aizen Pro`

### Remove from sidebar

- Remove `Chat` as a top-level settings destination.

### Keep, but narrow the scope

- `Terminal` stays for terminal behavior, session persistence, copy processing, and presets.
- `Editor` stays for editing behavior, indentation, minimap, line wrapping, gutter, and file browser behavior.

`Terminal` and `Editor` should stop owning their own theme pickers.

## Scope

### In scope

- Add a new `Appearance` page in Settings.
- Make Ghostty themes the single shared theme source.
- Move visual controls out of `Terminal`, `Editor`, and `Chat`.
- Remove the top-level `Chat` settings page.
- Introduce a shared appearance settings model instead of resolving appearance from scattered `@AppStorage` keys.
- Define migration from existing stored settings.

### Out of scope

- Redesigning every settings screen visually.
- Per-worktree or per-session appearance overrides.
- User-imported custom theme files.
- A full typography redesign for the app shell outside the settings model cleanup.

## Proposed Information Architecture

## 1. New `Appearance` page

The `Appearance` page becomes the visual control center for the whole app.

### Section: Theme

- `Use different themes for Light/Dark mode`
- `Dark Theme`
- `Light Theme`
- Theme preview cards showing:
  - app surface background
  - divider/border color
  - terminal sample
  - code sample
  - markdown sample

Product rule:

- This theme is the base theme for the entire app.
- There is no separate editor theme picker.
- There is no separate chat theme picker.

### Section: Terminal Typography

- `Font Family`
- `Font Size`

This continues to control the actual terminal renderer.

### Section: Code Typography

- `Font Family`
- `Font Size`
- `Diff Font Size`
- Optional `Use terminal font` toggle

Product rule:

- Code inherits the shared appearance theme colors.
- Code typography can differ from terminal typography.

### Section: Markdown Typography

- `Font Family`
- `Font Size`
- `Paragraph Spacing`
- `Heading Spacing`
- `Content Padding`

Product rule:

- Markdown inherits colors from the shared appearance theme.
- Markdown typography and spacing can be tuned separately from terminal/code.

### Section: Reset

- `Reset Appearance to Defaults`

This should reset only appearance-related keys, not editor behavior or terminal behavior.

## 2. `Terminal` page after redesign

Keep only terminal-specific behavior:

- terminal notifications
- progress overlays
- voice input button
- copy text processing
- session persistence
- tmux management
- terminal presets

Remove from `Terminal`:

- theme picker
- font picker
- font size

Those move to `Appearance`.

## 3. `Editor` page after redesign

Keep only editing/file behavior:

- line numbers / gutter
- line wrapping
- minimap
- indentation
- tabs vs spaces
- hidden files in file browser

Remove from `Editor`:

- theme picker
- font family
- font size
- diff font size

Those move to `Appearance`.

## 4. `Chat` page after redesign

Remove the top-level `Chat` page entirely for now.

Current `Chat` settings are purely presentational, so they belong under `Appearance`.

If Aizen later gains chat-specific behavioral settings, a new `Chat` page can be reintroduced with a narrower scope.

## Shared Appearance Rules

## Theme source of truth

Ghostty themes are the only supported theme catalog for now.

The shared appearance theme should provide:

- app background/surfaces
- dividers and borders
- terminal colors
- editor/code colors
- diff colors
- markdown colors
- inline code colors
- chat bubble-related accents where appropriate

## Typography rules

Use three explicit typography groups:

- terminal typography
- code typography
- markdown typography

This is more understandable than tying everything to one font while still avoiding separate theme systems.

## Markdown rules

Markdown presentation should be theme-derived, not a standalone theme system.

That means:

- markdown text/link/code colors come from the shared appearance theme
- markdown spacing comes from appearance settings
- markdown should not define its own independent theme picker

## Data Model

Introduce a single appearance model instead of storing appearance logic in unrelated views.

Recommended shape:

- `AppearanceSettings`
  - `usePerAppearanceTheme: Bool`
  - `darkThemeName: String`
  - `lightThemeName: String`
  - `terminalFontFamily: String`
  - `terminalFontSize: Double`
  - `codeFontFamily: String`
  - `codeFontSize: Double`
  - `diffFontSize: Double`
  - `markdownFontFamily: String`
  - `markdownFontSize: Double`
  - `markdownParagraphSpacing: Double`
  - `markdownHeadingSpacing: Double`
  - `markdownContentPadding: Double`

Recommended support types:

- `AppearanceSettingsStore`
- `AppearanceThemeResolver`
- `AppearanceTypographyResolver`
- `AppearanceMarkdownResolver`

The important part is not the exact type names. The important part is that views stop resolving appearance rules independently.

## Storage

Preferred direction:

- centralize keys under an `appearance.*` namespace or an equivalent constant-backed wrapper
- stop introducing new raw string keys in view files

Implementation requirement:

- leaf views should read resolved appearance values
- leaf views should not each decide how dark/light theme selection works

## Runtime Resolution

Appearance should be resolved once and reused.

### Theme resolution

One resolver should answer:

- effective theme name for current color scheme
- effective `VVTheme`
- effective app surface background
- effective divider color

### Typography resolution

One resolver should answer:

- effective terminal font
- effective code font
- effective diff font
- effective markdown font

### Markdown resolution

One resolver should answer:

- markdown theme colors derived from the active Ghostty theme
- markdown spacing values from appearance settings

This is especially important because markdown is currently split between:

- `MarkdownView`
- `ChatMessageList`

Those two renderers should not drift.

## Migration Plan

## Theme migration

Use terminal theme settings as the source of truth during migration because they already drive:

- app surfaces
- settings surfaces
- terminal rendering
- parts of chat styling

Migration rule:

- `appearance.darkThemeName` <- existing `terminalThemeName`
- `appearance.lightThemeName` <- existing `terminalThemeNameLight`
- `appearance.usePerAppearanceTheme` <- existing `terminalUsePerAppearanceTheme`

### Editor theme migration

Recommended product decision:

- do not preserve a separate editor theme after migration
- editor visuals converge onto the shared appearance theme

If users had a different editor theme configured before, that difference is intentionally removed by the redesign.

This is a simplification, not a bug.

## Typography migration

- terminal font values migrate from `terminalFontName` and `terminalFontSize`
- code font values migrate from `editorFontFamily`, `editorFontSize`, and `diffFontSize`
- markdown font values migrate from `chatFontFamily` and `chatFontSize`

## Spacing migration

- `chatBlockSpacing` should map into `appearance.markdownParagraphSpacing` as a best-effort seed

Even though the current app does not apply that value consistently, it should still be carried forward.

## Old keys

After migration:

- old theme keys should no longer be the runtime source of truth
- reads should move to the shared appearance model
- legacy keys can be cleaned up after one stable release if needed

## UI Notes

The `Appearance` page should feel like a control center, not another plain form dump.

Recommended layout:

- left: grouped settings form
- right: live preview stack

Preview stack should include:

- app shell surface sample
- terminal sample
- code snippet sample
- markdown sample

This is important because the whole point of the redesign is to show that one theme choice affects multiple surfaces coherently.

## Implementation Notes

## Views that should stop owning theme logic

This redesign should eventually remove duplicated appearance resolution from:

- app shell background helpers
- terminal split/diff/chat surface helpers
- code editor views
- diff views
- markdown views
- settings screens

## Views that should consume the shared appearance model

At minimum:

- `SettingsView`
- `TerminalSettingsView`
- `EditorSettingsView`
- `ChatMessageList`
- `MarkdownView`
- `CodeEditorView`
- `VVCodeSnippetView`
- `DiffView`
- app/window surface helpers

## Acceptance Criteria

- Settings contains a top-level `Appearance` page.
- `Chat` is removed as a top-level settings page.
- `Terminal` no longer exposes theme or font controls.
- `Editor` no longer exposes theme or font controls.
- Switching the appearance theme updates app surfaces, terminal, editor, diff, and chat/markdown visuals.
- Markdown spacing controls affect both major markdown rendering paths.
- Existing users keep their terminal, code, and chat font choices after migration.
- The app has one clear appearance source of truth.

## Open Questions

These should be resolved before implementation starts:

- Should code typography default to `Use terminal font = on`, or should code always remain independently configurable?
- Should markdown default to `System Font` or inherit code/terminal font by default?
- Do we want separate preview tabs for Light and Dark mode, or one preview with a mode toggle?
- Do we want a small “advanced overrides” section later, or should the redesign intentionally forbid per-surface theme divergence?

## Recommendation

Proceed with the strict version of the redesign:

- one shared Ghostty-based appearance theme
- separate typography groups for terminal, code, and markdown
- markdown spacing under `Appearance`
- `Chat` removed from the sidebar
- `Terminal` and `Editor` narrowed to behavioral settings only

That gives Aizen a much clearer model:

- one theme system
- three typography groups
- fewer top-level settings categories
- less duplicated runtime logic
