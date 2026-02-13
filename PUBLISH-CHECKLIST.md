# Publish Checklist

Things to fix before distributing through the Mac App Store or other channels.

## App Sandbox

- **Status**: Disabled (`ENABLE_APP_SANDBOX = NO`)
- **Required for**: Mac App Store
- **Issue**: Auto-reopen last file uses raw file paths in UserDefaults, which a sandboxed app can't access.
- **Fix**: Use security-scoped bookmarks to persist file access across launches. Store bookmark data in UserDefaults instead of plain paths.
- **Files**: `Sources/ChoirController/SequencerModel.swift` (`loadLastFileIfAvailable`, `addToRecentFiles`)
