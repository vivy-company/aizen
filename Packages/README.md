# Local CodeEdit Packages

All CodeEdit packages are forked locally for full control and modification.

## Packages Included

- **CodeEditSourceEditor** - Modified with enhanced syntax highlighting (markdown, Swift function calls, etc.)
- **CodeEditLanguages** - Tree-sitter language grammars
- **CodeEditTextView** - Text view component
- **CodeEditSymbols** - SF Symbols integration

## Changes Made

### CodeEditSourceEditor
- Added markdown captures: `@text.title`, `@text.emphasis`, `@text.strong`, `@text.uri`, `@text.literal`, `@text.reference`
- Added Swift captures: `@function.call`, `@function.macro`, `@operator`, `@label`, `@string.regex`
- Added general captures: `@punctuation.special`, `@punctuation.delimiter`, `@string.escape`
- Updated `EditorTheme.mapCapture()` to properly style all new captures

## Setup in Xcode

Since these are removed from git tracking (no .git folders), they're standalone packages you can modify freely.

To add them to your Xcode project:

1. Open `aizen.xcodeproj` in Xcode
2. **File** → **Add Package Dependencies...**
3. Click **"Add Local..."** (bottom left)
4. Navigate to and select each package:
   - `/Users/uyakauleu/development/aizen/Packages/CodeEditSourceEditor`
   - `/Users/uyakauleu/development/aizen/Packages/CodeEditLanguages`
   - `/Users/uyakauleu/development/aizen/Packages/CodeEditTextView`
   - `/Users/uyakauleu/development/aizen/Packages/CodeEditSymbols`
5. For each, click "Add Package"
6. Clean Build Folder (Cmd+Shift+K)
7. Build (Cmd+B)

## Modifying Packages

You can now freely edit any file in these packages:
- Changes take effect immediately on rebuild
- No git conflicts or upstream issues
- Full control over all CodeEdit components

## Notes

- These are NOT git submodules - they're independent copies
- Relative paths will work on any machine
- You can commit changes to these packages in your main aizen repo
