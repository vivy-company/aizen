# OpenCode Plugin Detection Strategy

## Problem
Users install OpenCode plugins via various package managers (npm, volta, nvm, fnm, asdf, pnpm, bun, yarn). Each has different installation paths and detection methods.

## Solution: Multi-Manager Detection

### Detection Strategy (in priority order)

1. **Direct File System Checks** (Primary - No shell needed)
   - Check common binary locations directly
   - Fast, reliable, no PATH issues
   
2. **Shell Command Fallback**
   - `which <packageName>` as final fallback
   - Relies on user's PATH being correct

### Supported Package Managers

| Manager | Binary Path | Package.json Path |
|---------|------------|-------------------|
| **Volta** | `~/.volta/bin/{package}` | `~/.volta/tools/image/packages/{package}/lib/node_modules/{package}/package.json` |
| **NVM** | `~/.nvm/versions/node/{version}/bin/{package}` | `~/.nvm/versions/node/{version}/lib/node_modules/{package}/package.json` |
| **FNM** | `~/.fnm/aliases/default/bin/{package}` | `~/.fnm/node-versions/{version}/installation/lib/node_modules/{package}/package.json` |
| **asdf** | `~/.asdf/shims/{package}` | `~/.asdf/installs/nodejs/{version}/lib/node_modules/{package}/package.json` |
| **pnpm** | `~/.local/share/pnpm/{package}` | `~/.local/share/pnpm/global/5/node_modules/{package}/package.json` |
| **bun** | `~/.bun/bin/{package}` | `~/.bun/install/global/node_modules/{package}/package.json` |
| **Homebrew** | `/opt/homebrew/bin/{package}` | N/A |
| **System** | `/usr/local/bin/{package}` | N/A |

### Implementation Details

#### `isInstalled(_ packageName: String)`
1. Checks all binary paths directly via FileManager
2. For version managers (nvm, fnm, asdf), finds latest version
3. Falls back to `which` command if file system checks fail

#### `getInstalledVersion(_ packageName: String)`
1. Searches for `package.json` in all manager-specific paths
2. Parses version from `package.json`
3. Falls back to shell commands (`volta list`, `npm list -g`)

### Why This Works
- **No PATH dependencies**: Direct file system checks work regardless of shell environment
- **No shell command failures**: Primary detection doesn't rely on subprocess execution
- **Multi-manager support**: Handles all common Node.js installation methods
- **Version-aware**: For managers with multiple Node versions, finds latest

### Known Limitations
- pnpm path uses hardcoded version (`global/5`) - may need updating
- Yarn Berry (v2+) has dynamic paths - not fully supported
- Custom npm prefix locations not detected

### Testing
```bash
# Verify binary exists
ls -la ~/.volta/bin/oh-my-opencode
ls -la ~/.nvm/versions/node/*/bin/oh-my-opencode

# Verify package.json exists
cat ~/.volta/tools/image/packages/oh-my-opencode/lib/node_modules/oh-my-opencode/package.json | grep version
cat ~/.nvm/versions/node/*/lib/node_modules/oh-my-opencode/package.json | grep version
```

## Future Improvements
1. Add user preference for package manager (manual override)
2. Cache detection results to avoid repeated file system checks
3. Add support for custom npm prefix paths
4. Better Yarn Berry (v2+) support
