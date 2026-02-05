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

### 2. Connecting a Doll

1. **Wake the Doll**: Tap the doll's head or press its button to wake it up.
2. **Enter Pairing Mode**:
   - Press and **hold** the button on the doll (usually on the back or bottom module).
   - Keep holding until the doll sings **"Searching for controller"**.
3. **Connect in App**:
   - In the Choir Controller app sidebar, click **Scan**.
   - You should see the doll appear in the "Discovered" list (often named "TE-Choir" or similar).
   - Click **Connect**.
   - If prompted for a PIN, enter `000000`.
   - The doll should sing **"Connected to the controller"**.

### 3. Playing

- Click the piano keys to play notes.
- Use the **"Local Audio Monitor"** toggle to hear a synthesized tone from your Mac speakers along with the doll.
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
