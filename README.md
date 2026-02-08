# Choir Arranger

A native macOS sequencer for arranging and performing with [Teenage Engineering's Choir dolls](https://teenage.engineering/products/choir) via Bluetooth MIDI.

Built on protocol research from [jetztgradnet/Choirama](https://github.com/jetztgradnet/Choirama).

## Features

- **Piano Roll Sequencer**: Add, drag, and resize MIDI notes on a grid. Each note carries pitch, velocity, and Choir-specific phoneme controls (consonant, vowel, vibrato, reverb).
- **Playback Engine**: Play arrangements at a configurable tempo with a green playhead. Supports up to 8-voice polyphony. Notes trigger on playhead contact and release when the playhead passes the note end.
- **Scrub Zone**: Click or drag the transport bar to scrub through your arrangement. The scrub zone scrolls in sync with the piano roll grid.
- **Scale Helper**: Toggle an overlay that highlights in-key vs. out-of-key rows. Supports major, minor, harmonic minor, dorian, mixolydian, and pentatonic scales.
- **File Persistence**: Save and load sequences as `.choir` files (JSON). Recent files are tracked and the last opened file auto-loads on launch.
- **Bluetooth MIDI**: Connect to Choir dolls and other BLE MIDI devices. (Note: the in-app BLE scanner is not yet functional -- use macOS Audio MIDI Setup to pair dolls for now.)
- **Virtual Keyboard**: Interactive piano keyboard with Middle C highlighted. Pressing a key scrolls the grid to that pitch and highlights the row.
- **Local Audio Monitor**: Optional built-in synthesizer to hear playback without a connected doll.

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

- Click the grid to add notes. Drag to reposition, drag the right edge to resize.
- Use the bottom inspector to set consonant, vowel, velocity, vibrato, and reverb per note.
- Press Play or use the scrub zone to hear your arrangement.
- Save your work as a `.choir` file (Cmd+S). Open Recent is in the File menu.
- Toggle the scale helper in the toolbar to visualize notes in your chosen key.

## Architecture

| Component | Role |
|---|---|
| `SequencerModel` | Data model for notes, playback state, file I/O, and scale helper |
| `SequencerView` | Transport bar, playback timer, MIDI triggering engine |
| `PianoRollView` | Grid rendering, note display, drag/resize gestures, playhead line |
| `MidiService` | CoreMIDI integration via MIDIKit, NoteOn/NoteOff/CC messaging |
| `BluetoothMidiManager` | CoreBluetooth scanning and peripheral connections |
| `AudioMonitorService` | AVAudioEngine-based local synthesizer |
| `KeyboardView` | Interactive piano keyboard with pitch highlighting |

## Dependencies

- [MIDIKit](https://github.com/orchetect/MIDIKit) -- MIDI I/O for Swift

## Credits

- Protocol research: [jetztgradnet/Choirama](https://github.com/jetztgradnet/Choirama)
- Hardware: [Teenage Engineering Choir](https://teenage.engineering/products/choir)
