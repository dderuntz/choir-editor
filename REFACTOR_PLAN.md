# Refactor Plan

Post-Xcode migration cleanup. Tracked items, roughly priority ordered.

## 1. Break up ContentView.swift — DONE
Extracted four types into their own files:
- `FileMenuActions` → `FileMenuActions.swift`
- `ConnectionStatusView` → `ConnectionStatusView.swift`
- `SettingsPanelView` → `SettingsPanelView.swift`
- `SliderWithDefault` → `SliderWithDefault.swift`

Removed unused `import MIDIKitIO` from ContentView. ContentView went from 489 → 253 lines.

## 2. Delete dead ConnectionView.swift — DONE
Removed orphaned `ConnectionView` (source + symlink). Was never used.

## 3. Deduplicate pitch utilities — DONE
`KeyboardView` and `SoundPadView` now delegate to `PitchConstants` instead of duplicating
`isBlackKey()`, `noteName()`, and pitch range constants.

## 4. Clean up SoundPadView.swift — DONE
Removed dead functions: `retriggerTestButton`, `runBaselineTest`, `playLiveGlide`.
958 → 885 lines. Still large but no dead code remaining.

Also moved "Local Audio Monitor" → "Local Synth Monitor" in the MIDI menu.

## 5. Pull file dialogs out of SequencerModel — DONE
Moved `showSaveDialog()`, `showOpenDialog()`, and `saveCurrentOrPrompt()` from
`SequencerModel` into `FileMenuActions`. Model keeps pure `save(to:)`/`load(from:)`.
`FileCommands` (OS menu bar) now routes through `FileMenuActions.shared`.
Removed unused `import UniformTypeIdentifiers` from SequencerModel.

## 6. Slim down ChoirControllerApp.swift
Four `Commands` structs (`ViewCommands`, `MidiCommands`, `EditCommands`, `FileCommands`) could live in a `MenuCommands.swift`.

## 7. Future: App Sandbox + security-scoped bookmarks
Currently sandbox is disabled for dev. Before Mac App Store, need to re-enable sandbox and use security-scoped bookmarks for file access.
