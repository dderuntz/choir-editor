# Choir Arranger

A native macOS app for arranging and performing with [Teenage Engineering's Choir dolls](https://teenage.engineering/products/choir) via Bluetooth MIDI.

![Choir Arranger](docs/screenshot.png)

## Download

**[Download Choir Arranger](https://github.com/dderuntz/choir-editor/releases/latest/download/ChoirArranger.zip)** — signed and notarized.

Unzip and drag to Applications. No Xcode or build tools needed.

### Requirements
- macOS 13+ (Composer features require macOS 26+)
- Apple Silicon or Intel Mac

## Features

- **Piano Roll Sequencer** — click to place notes, drag to move/resize, shift-drag for marquee selection
- **Text-to-Song Composer** — type words, generate lyrics, hear them sung with bouncing ball playback
- **4 Synth Engines** — DeFormant (source-filter), Animalese (sample-based), Speak & Spell (LPC), FOF (impulse-driven)
- **4-Part Barbershop** — shift-click phoneme chips to enable ensemble harmony
- **Swedish Language Support** — full UI localization + 823k-word phoneme dictionary
- **MIDI Export** — standard .mid files with CC data for consonant, vowel, vibrato, reverb
- **Guided Onboarding** — contextual tips for both Composer and Piano Roll workflows
- **Dark Mode** — full support across all views

## Getting Started

### Connect a Doll

1. **Wake your dolls** — give each one a tap.
2. **Choose your lead doll** — long-press its connect button until it sings *"Searching for controller."*
3. Click the **Connect** button in the toolbar. The app opens the macOS Bluetooth MIDI window.
4. Click **Advertise** in the Bluetooth window. The doll should connect and sing *"Connected to MIDI controller."*
5. Enter the **PIN code** shown in the app when prompted.

The app detects the doll automatically once paired and closes the setup panel.

### Piano Roll

| Action | How |
|---|---|
| Add a note | Click on the grid |
| Move a note | Drag it |
| Resize a note | Drag its right edge |
| Duplicate a note | Option-drag |
| Select multiple notes | Shift-click or shift-drag (marquee) |
| Move a group | Drag any selected note |
| Edit a group | Change any inspector parameter — applies to all selected |
| Delete | Select and press Delete |
| Play / Stop | Click the play button or press Space |
| Scrub | Click or drag the transport bar |
| Scale guide | Toggle in the toolbar — hatches out-of-key rows |
| Save / Open | Cmd+S / Cmd+O, or use File > Open Recent |

### Note Inspector

Each note carries five parameters that control the doll's voice:

- **Consonant** — the attack sound (None, B, D, G, H, L, M, N, R, S, T, W, Y, Random)
- **Vowel** — the sustained sound (Ah, Eh, Ee, Oh, Oo, Random)
- **Velocity** — how loud (0-127)
- **Vibrato** — pitch modulation depth (0-127)
- **Reverb** — room effect (0-127)

### Composer Mode

Type words, generate lyrics, and hear them sung. Toggle from the toolbar or View menu.

| Action | How |
|---|---|
| Enter a theme | Type a word or phrase in the text field |
| Generate lyrics | Click the Recompose button — the on-device model writes a lyric from your theme |
| Extract phonemes | Click Reveal Phonemes — text is decomposed into singable syllable chips |
| Play back | Click Play — phonemes play with pitch and timing based on the selected scale |
| Edit a chip | Click to open the inspector (consonant, vowel, harmony) |
| Ensemble harmony | Shift-click or long-press a chip for 4-part barbershop |
| Send to sequencer | Click Copy to Piano Roll |
| Recompose styles | Senryu, Bellman, Kulning, Dada, Nursery Rhyme |

### Keyboard

The bottom keyboard lets you play notes live. Clicking a key scrolls the grid to that pitch. Out-of-scale keys are hatched when a scale is active. In Composer mode, keys step through phoneme chips at the pressed pitch.

### Language

Switch between English and Swedish via Help > Language. The UI updates instantly without restarting. The Composer uses a language-appropriate phoneme dictionary and lyric style set.

### MIDI Export

**File > Export as MIDI...** (Cmd+Shift+E) saves your arrangement as a standard `.mid` file.

| CC | Parameter |
|---|---|
| CC1 | Vibrato (Modulation) |
| CC2 | Consonant (Breath) |
| CC3 | Vowel |
| CC4 | Reverb (Foot Control) |

## How AI Is Used

Choir Arranger uses **Apple Foundation Models** (on-device, macOS 26+) for two optional features in the Composer:

1. **Lyric generation** — when you click a Recompose button, the on-device model writes a short lyric from your theme words. The model runs entirely on your Mac. No text is sent to any server.

2. **Text normalization** — before phoneme extraction, the model cleans up typos and formatting. If this fails or is unavailable, the raw text is used instead.

**What AI does NOT do:**
- Phoneme extraction uses offline dictionaries (CMU Pronouncing Dictionary for English, OpenSLR #29 for Swedish) — no AI involved
- Playback, synthesis, MIDI, and all audio processing are deterministic code — no AI involved
- The app works fully without AI features (macOS 13+). AI features require macOS 26+ with Apple Intelligence enabled

**Privacy:** All AI processing happens on-device via Apple's framework. No data leaves your Mac. No accounts, no telnet, no analytics.

## Building from Source

Requires macOS 13+ and Xcode 15+.

```bash
swift run
```

Or use the Xcode project in `Choir Arranger/`.

## Feedback

Found a bug or have a feature request? [Open an issue](https://github.com/dderuntz/choir-editor/issues).

## Credits

- Protocol research: [jetztgradnet/Choirama](https://github.com/jetztgradnet/Choirama)
- Hardware: [Teenage Engineering Choir](https://teenage.engineering/products/choir)
- English phonemes: [CMU Pronouncing Dictionary](http://www.speech.cs.cmu.edu/cgi-bin/cmudict)
- Swedish phonemes: [OpenSLR #29](https://www.openslr.org/29/) (CC BY 4.0, NST / Riksbankens Jubileumsfond)
