# Focale

**The premium screenshot tool for macOS.** One shortcut, one bar: capture, annotate, and share in under 3 seconds.

Focale replaces the built-in screenshot utility with a faster flow and a native, premium interface. Everything is processed on-device — no image ever leaves your Mac.

## Features

- **One shortcut** (`Cmd + Shift + 5`, customizable) opens the floating capture bar
- **Capture modes**: area, window, full screen, with one-key switching
- **Visible destination**: clipboard, file, or both — never buried in a submenu
- **Repeat last area** with a button or dedicated shortcut
- **Precise areas**: exact sizes (e.g. 1080×720) and ratios (16:9, 4:3, 1:1)
- **Quick annotation**: arrow, shapes, text, highlighter, blur, pixelate, step numbering, magnifier
- **Floating thumbnail**: copy, save, annotate, share, or delete on hover
- **History panel**: search (OCR-indexed), pinning, drag-and-drop to any app
- **OCR**: copy text from any area (French + English)
- **Presets**: Support, Tutorial, Email — destination, format, and annotation in one click
- **Screen recording**: area or fullscreen, MP4 / GIF export
- **Accessible**: VoiceOver labels, full keyboard control, reduced-motion and contrast support

## Requirements

- macOS 14 Sonoma or later (optimized for macOS 26)
- Apple Silicon or Intel
- Xcode 17+ and Swift 6 to build from source

## Install & Run

Clone the repository, then either open the project in Xcode:

```sh
open Focale/Focale.xcodeproj
```

and press `⌘R`, or build from the terminal:

```sh
xcodebuild -project Focale/Focale.xcodeproj -scheme Focale -configuration Debug build
xcodebuild -project Focale/Focale.xcodeproj -scheme Focale test
```

On first launch, Focale guides you through granting the **Screen Recording** permission and choosing your shortcut and default destination.

## Usage

1. Press `Cmd + Shift + 5` — the screen dims and the capture bar appears.
2. Drag an area (live dimensions + 8× magnifier), or press `2` / `3` for window / fullscreen.
3. Release: the capture is already in your clipboard (or saved, per your destination).
4. Click the thumbnail to annotate: `A` arrow, `T` text, `B` blur, `N` numbering.
5. Press `Cmd + Shift + H` anytime to browse your history.

## Configuration

All settings live in `Focale → Settings…` (`⌘,`):

| Tab | Controls |
| --- | -------- |
| General | Default destination, login item, thumbnail timeout, shutter sound |
| Shortcuts | Capture, history, and repeat-last-area shortcuts |
| Destination | Save folder, PNG / JPEG format, file-name pattern |
| Presets | One-click Support / Tutorial / Email configurations |
| Appearance | System / light / dark theme |
| Privacy | Local-only processing, optional anonymous stats, clear history |

## How It Works

| Capability | Technology |
| ---------- | ---------- |
| Screenshot & recording | ScreenCaptureKit |
| Global shortcut | System hot-key registration |
| Selection overlay | Non-activating multi-display panels |
| Blur / pixelate | Core Image |
| OCR & sensitive-data hints | Vision + on-device patterns |
| History & search | SwiftData + OCR index |
| Sharing | Native share sheet |
| Login item | SMAppService |
| Automation | App Intents (Shortcuts) |

## Project Structure

```
Focale/
├── Focale.xcodeproj/   Xcode project + shared scheme
├── Tools/              Helper scripts (app-icon generator)
├── Focale/             App sources (SwiftUI + AppKit where needed)
└── FocaleTests/        Swift Testing suite
```

Key areas: `Bar/` (capture bar), `Overlay/` (selection), `Toast/` (thumbnail),
`Editor/` (annotation), `History/`, `Settings/`, `Onboarding/`,
`DesignSystem/`, `Core/` (models, geometry, imaging).

## Roadmap

- [x] Capture bar, selection overlay, annotation editor, history, settings
- [ ] Global shortcut + ScreenCaptureKit wiring
- [ ] OCR, SwiftData history, presets, video recording (v1.1)
- [ ] Scrolling capture, auto sensitive-data blur, Shortcuts, iCloud (v1.2+)

## Contributing

Issues and pull requests are welcome. Please keep the UI fast (< 150 ms to show the bar),
keyboard-first, and fully local — no network calls for capture data.
Run the test suite before submitting.

## Privacy

Focale processes everything locally. No account, no cloud upload, no telemetry
without your explicit opt-in.
