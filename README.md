# Choir Arranger

A native macOS sequencer for arranging and performing with [Teenage Engineering's Choir dolls](https://teenage.engineering/products/choir) via Bluetooth MIDI.

Built on protocol research from [jetztgradnet/Choirama](https://github.com/jetztgradnet/Choirama).

![Choir Arranger](docs/screenshot.png)

## Features

- **Piano Roll Sequencer**: Add, drag, and resize MIDI notes on a grid. Each note carries pitch, velocity, and Choir-specific phoneme controls (consonant, vowel, vibrato, reverb).
- **Alt-Drag to Duplicate**: Hold Option (Alt) while dragging a note to create a copy. Release on the original position to cancel.
- **Multi-Select & Group Edit**: Shift-click to select multiple notes. Drag to move them together. Edit parameters in the Note Inspector to apply the same value across all selected notes.
- **Note Coverage**: When a note is moved to fully cover another on the same pitch, the covered note is automatically removed.
- **Playback Engine**: Play arrangements at a configurable tempo with a green playhead. Supports up to 8-voice polyphony. Notes trigger on playhead contact and release when the playhead passes the note end.
- **Scrub Zone**: Click or drag the transport bar to scrub through your arrangement. The scrub zone scrolls in sync with the piano roll grid.
- **Scale Helper**: Toggle an overlay that hatches out-of-key rows with a diagonal pattern. Supports major, minor, harmonic minor, dorian, mixolydian, and pentatonic scales.
- **File Persistence**: Save and load sequences as `.choir` files (JSON). Recent files are tracked and the last opened file auto-loads on launch.
- **Bluetooth MIDI**: Connect to Choir dolls and other BLE MIDI devices. (Note: the in-app BLE scanner is not yet functional -- use macOS Audio MIDI Setup to pair dolls for now.)
- **Virtual Keyboard**: Interactive piano keyboard with Middle C highlighted. Pressing a key scrolls the grid to that pitch and highlights the row.
- **Local Audio Monitor**: Built-in triangle wave synthesizer with pitch vibrato (4.5 Hz, 1-second ramp-in envelope) and AVAudioUnitReverb (cathedral preset). Vibrato depth and reverb wet/dry are driven by each note's CC values.
- **Light & Dark Mode**: Full support for system appearance. The UI adapts colors across the grid, toolbar, inspector, explorer, settings, and connect panels. Transport bar and piano keys retain their fixed styling.

## Prerequisites

- macOS 13.0 or later
- Xcode 15+ (for building)
- A Teenage Engineering Choir doll (for full MIDI testing)

## Getting Started

### Build and Run

**Option A: VS Code / Cursor (Recommended)**
1. Open "Run and Debug" (Cmd+Shift+D).
2. Select **"Run ChoirController"**.
3. Click Play.

**Option B: Terminal**
```bash
swift run
```

**Option C: Bundled App**
```bash
make bundle
open ChoirController.app
```

### Connecting a Doll

Choir dolls must be paired through macOS **Audio MIDI Setup** before the app can control them (one-time setup per doll):

1. Open **Audio MIDI Setup** (Spotlight or `/Applications/Utilities/`).
2. Menu bar: Window > Show MIDI Studio (Cmd+2).
3. Click the Bluetooth icon in the toolbar.
4. Wake the doll (press its button).
5. Click **Connect** when it appears (e.g., "CH-8").

Once paired, the doll appears as a MIDI destination that Choir Arranger detects automatically.

### Using the Sequencer

- **Add notes**: Click the grid to place a note.
- **Move / resize**: Drag a note to reposition. Drag the right edge to resize.
- **Duplicate**: Hold Option (Alt) and drag a note to create a copy.
- **Multi-select**: Shift-click to add notes to the selection. Drag to move them together.
- **Group edit**: With multiple notes selected, change any parameter in the inspector to apply it to all.
- **Inspector**: Set consonant, vowel, velocity, vibrato, and reverb per note (or per group).
- **Playback**: Press Play or scrub the transport bar. The window is draggable from any non-interactive area.
- **Scale guide**: Toggle in the toolbar to hatch out-of-key rows with a diagonal pattern.
- **Save / Load**: Save as `.choir` (Cmd+S). Open Recent is in the File menu.
- **Appearance**: Switch between Light, Dark, or System appearance in the View menu.

## Architecture

| Component | Role |
|---|---|
| `SequencerModel` | Data model for notes, playback state, file I/O, scale helper, and undo |
| `SequencerView` | Transport bar, playback timer, MIDI triggering engine, note inspector |
| `PianoRollView` | Grid rendering, note display, drag/resize/duplicate gestures, playhead |
| `NoteRectView` | Individual note: move, resize, alt-drag duplicate, multi-select |
| `MidiService` | CoreMIDI integration via MIDIKit, NoteOn/NoteOff/CC messaging |
| `BluetoothMidiManager` | CoreBluetooth scanning and peripheral connections |
| `AudioMonitorService` | Triangle wave synth with ADSR, pitch vibrato, and reverb (AVAudioEngine) |
| `KeyboardView` | Interactive piano keyboard with pitch highlighting |
| `Theme` | Centralized color tokens with light/dark scheme-aware helpers |
| `SoundPadView` | Explorer panel for MIDI CC controls and console |

## Dependencies

- [MIDIKit](https://github.com/orchetect/MIDIKit) -- MIDI I/O for Swift

## Credits

- Protocol research: [jetztgradnet/Choirama](https://github.com/jetztgradnet/Choirama)
- Hardware: [Teenage Engineering Choir](https://teenage.engineering/products/choir)
