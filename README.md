# Choir Controller

A native macOS application for controlling [Teenage Engineering's Choir dolls](https://teenage.engineering/products/choir) via Bluetooth MIDI.

![Choir App Screenshot](https://via.placeholder.com/800x400?text=App+Screenshot+Placeholder)

## Features

- **Bluetooth MIDI Connectivity**: Scan, discover, and connect to Choir dolls (and other BLE MIDI devices).
- **Virtual Keyboard**: Full 88-key piano interface to play notes on the dolls.
- **Local Audio Monitor**: Built-in square wave synthesizer to hear what you play locally (useful for debugging or playing without the doll).
- **Ghost Track Scrolling**: Auto-scrolls to Middle C on startup.

## Prerequisites

- macOS 13.0 or later
- Xcode 15+ (for building)
- A Teenage Engineering Choir doll (for full testing)

## Getting Started

### 1. Build and Run

You can run the app directly from the command line or VS Code.

**Option A: VS Code (Recommended)**
1. Open the "Run and Debug" sidebar (Cmd+Shift+D).
2. Select **"Run ChoirController"**.
3. Click the green Play button (▶).

**Option B: Terminal**
```bash
swift run
```
*Note: The app includes a helper to ensure it activates as a foreground window when run from the CLI.*

### 2. Connecting a Doll (One-Time Setup via MIDI Studio)

Currently, Choir dolls must be paired through macOS **Audio MIDI Setup** before the app can control them. This is a one-time setup per doll.

1. **Open Audio MIDI Setup**: Spotlight search "Audio MIDI Setup" or find it in `/Applications/Utilities/`.
2. **Open MIDI Studio**: Menu bar → Window → Show MIDI Studio (or Cmd+2).
3. **Open Bluetooth Configuration**: Click the Bluetooth icon in the toolbar.
4. **Wake the Doll**: Press the button on the doll to wake it. The doll should start advertising.
5. **Connect**: The doll should appear in the device list (e.g., "CH-8"). Click **Connect**.
6. **Verify**: The doll should now appear in MIDI Studio's device list with up/down arrows indicating active ports.

Once paired, the doll will appear as a MIDI destination that the Choir Controller app can use automatically.

> **Note**: We plan to add direct BLE MIDI connection in a future update to eliminate this MIDI Studio step.

### 3. Playing

- Launch the app - it should auto-detect your paired Choir doll and show "MIDI Destination: CH-8" in green.
- Click the piano keys to play notes on the doll.
- Use the **"Local Audio Monitor"** toggle (off by default) to hear a synthesized tone from your Mac speakers.
- The keyboard covers the full 88-key range (A0 to C8). Middle C is marked in **Yellow**.

## Architecture

- **MidiService**: Handles CoreMIDI integration and message sending.
- **BluetoothMidiManager**: Manages CoreBluetooth scanning and peripheral connections.
- **AudioMonitorService**: A custom thread-safe audio engine using `AVAudioSourceNode` for local synthesis.

## Development

This project uses **Swift Package Manager**.
- **Linting**: Run `swift build` to check for errors.
- **Rules**: Check `.cursor/rules` for coding standards.

## Credits

- Built for the Teenage Engineering Choir series.
- Protocol research based on [jetztgradnet/Choirama](https://github.com/jetztgradnet/Choirama).
