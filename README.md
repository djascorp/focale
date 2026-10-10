# Focale — Premium Screenshot Tool for macOS

One shortcut, one bar: capture, annotate, and share in under 3 seconds.
A premium interface that feels like part of macOS, with 100% on-device processing.

## Status: UI Phase (Design)

All PRD §7.2 screens are implemented in SwiftUI and previewable in the
**UI gallery** (the main window at launch):

- Floating capture bar (modes, visible destination, timer, repeat, Capture)
- Selection overlay (handles, dimension badge, 8× magnifier, precise size F5)
- Floating preview toast (hover actions, swipe away, adjustable timeout)
- Working annotation editor (arrow, shapes, text, highlighter, blur,
  pixelate, step numbering, magnifier, undo/redo, PNG export)
- History (search, pinning, drag-and-drop)
- Settings (6 tabs, shortcut recorder, presets)
- Onboarding (3 screens, real TCC permission request)

System wiring (global shortcut, multi-display NSPanel overlay, ScreenCaptureKit,
Vision OCR, SwiftData, video recording) comes in the next phases.

## Requirements

- macOS 14+ (optimized for macOS 26), Xcode 17+, Swift 6
- No external dependencies (Swift Package Manager: nothing yet)

## Build

```sh
# Icon (regenerates the 10 appiconset PNGs)
swift Focale/Tools/make_icon.swift

# Build
xcodebuild -project Focale/Focale.xcodeproj -scheme Focale -configuration Debug build

# Tests (Swift Testing)
xcodebuild -project Focale/Focale.xcodeproj -scheme Focale test
```

Or open `Focale/Focale.xcodeproj` in Xcode and run (⌘R).

## Structure

```
Focale/
├── Focale.xcodeproj/        Xcode project + shared scheme
├── Tools/                   scripts (icon generation)
├── Focale/                  app sources
│   ├── App/                 FocaleApp, AppState, AppSettings
│   ├── Core/                models, geometry, images, sensitive-data detection
│   ├── DesignSystem/        colors, typography, motion, components
│   ├── Bar/                 floating capture bar
│   ├── Overlay/             selection + magnifier + precise size
│   ├── Toast/               floating preview toast
│   ├── Editor/              model, canvas, inspector
│   ├── History/             history panel
│   ├── Settings/            settings + shortcut recorder
│   ├── Onboarding/          3 screens + logo
│   ├── ContentView.swift    UI gallery (temporary, design phase)
│   └── Resources/           Assets + Localizable (FR/EN)
└── FocaleTests/             Swift Testing (geometry, detection, editor)
```

## Roadmap (PRD §13)

1. **Core**: global shortcut, NSPanel, ScreenCaptureKit, destination, precise area
2. **Editing**: real timer, system thumbnail, crop
3. **v1.1**: Vision OCR, SwiftData history, presets, video
4. **v1.2+**: scrolling capture, auto sensitive-data blur, Shortcuts, iCloud
