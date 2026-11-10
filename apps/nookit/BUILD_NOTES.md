# Nookit native build notes

The macOS app is a SwiftUI prototype that compiles and runs from the command line without Xcode or SwiftPM. This file explains the non-obvious parts of the build and the remaining release work.

Verified with:

- macOS 27.2 (Apple silicon)
- Swift 6.0.3 / Swift Driver 1.115.1
- Command Line Tools only (`xcodebuild` unavailable)
- Deployment target `arm64-apple-macos14.0`

## Build

```bash
cd apps/nookit
./build-app.sh                 # release
CONFIG=debug ./build-app.sh    # debug symbols, no optimisation
open build/Nookit.app
```

`build-app.sh`:

1. finds every `Sources/Nookit/**/*.swift` file;
2. runs `swiftc -parse-as-library -swift-version 5 -target <arch>-apple-macos14.0 -sdk $(xcrun --show-sdk-path)`;
3. creates `build/Nookit.app/Contents/{MacOS,Resources}`;
4. copies the binary, `Info.plist`, and `Sources/Nookit/Resources/catalog.json`;
5. rasterizes `Assets/AppIcon.svg` with `qlmanage`, packs an `.icns` with `iconutil`, and copies it if successful;
6. ad-hoc signs the bundle with `codesign --sign -`.

The output is a normal double-clickable `.app`. `build/` is disposable.

## Why not `swift build`?

On this machine the Command Line Tools ship a `PackageDescription` module whose private `.swiftinterface` is newer than the compiler expects. Every manifest fails before app code compiles:

```
error: 'SwiftVersion' is not a member type of 'PackageDescription'
```

`Package.swift` is retained and uses `swiftLanguageModes: [.v5]` so it can be opened in Xcode or built on a machine with a matched toolchain. It is not the supported build path here. `build-app.sh` is the supported path.

The app is compiled in Swift 5 language mode because the AppKit/AVFoundation bridges produce non-Sendable warnings that are errors under Swift 6 strict concurrency. The remaining warnings are listed at the end of a build and are intentionally deferred.

## App structure

```
Sources/Nookit/
├── App/            NookitApp, AppDelegate, AppState, menu bar, startup
├── Core/           FilePicker, Formatters, Permissions, ResultStore, Shell, Theme
├── Models/         Catalog.swift (JSON shapes + loader), ToolContext
├── Notch/          NotchController, NotchView, settings, module views
├── Services/       AI, calendar, clipboard, notes, tasks, timers, music, health
├── Tools/          ToolRegistry + tool screens by area + shared ToolSupport
├── Views/          dashboard, sidebar, detail, settings, components
└── Resources/      catalog.json (copied into the bundle)
```

Tool screens are split by area: `Tools/` holds the original developer/text/foundation screens plus `ExtraVideoTools`, `ExtraAudioTools`, `ExtraImageTools`, `ExtraPDFTools`, `ExtraConvertTools`, `ExtraTextTools`, `ExtraMacTools`, `ExtraDisplayTools` and `CoordinatePickerTool`.

### Catalogue loading

`CatalogStore.shared` reads `catalog.json` from the app bundle first, then falls back to the source tree for development. It avoids `Bundle.module` because the direct `swiftc` build does not generate a SwiftPM resource bundle. If the file is missing or malformed, the app opens with an empty catalogue rather than trapping.

`shared/build-catalog.mjs` writes the same JSON to `Sources/Nookit/Resources/catalog.json`, so the website and app cannot disagree about counts, names, or status.

### Tool readiness

`Tools/ToolRegistry.swift` maps catalogue slugs to SwiftUI screens. A tool is Ready in the app only when a builder is registered. The current registry has 94 entries, matching the 94 `implemented: true` tools in the catalogue.

`ToolRegistry.readyCount(in:)` is used by the dashboard and sidebar. If you add a screen, add its slug to the registry; if you mark a roadmap tool implemented in the catalogue, add both at once.

Shared UI lives in `Tools/ToolSupport.swift`: `ToolPage`, `ToolCard`, `TextOutputCard`, `StatTile`, `OptionPicker`, file drop zones and result actions. Tool views read `ResultStore` and `AppState` from the environment.

### Results and destructive actions

`Core/ResultStore.swift` creates a dated folder per run inside a Nookit folder in Downloads. Original files are passed read-only to the tools; outputs get new names. Destructive operations (currently ejecting volumes) require an explicit confirmation in the relevant view; no tool overwrites an original.

### Notch

`Notch/NotchController.swift` owns a non-activating `NSPanel` positioned at the top centre of the active screen. It handles hover-open, click-to-pin, collapse-on-leave, and screen changes. Carbon global hotkeys open the clipboard, notes and AI modules from any app. The panel is excluded from screen capture with `sharingType = .none`. `NotchSettings` stores enabled modules in `UserDefaults`; notes, tasks and habits are stored as files under Application Support, while clipboard history and the water counter live in `UserDefaults`.

Implemented modules: AI Chat, Calendar, Clipboard, Notes, Tasks, Timers, Music, Hydration, Breathe, Habits. Dictation and the other 13 roadmap modules render as unavailable/soon states rather than pretending to work.

The expanded panel is positioned below the physical notch on notched Macs (`screen.frame.maxY - screen.safeAreaInsets.top`) instead of behind it, so Breathe, AI Chat and the taller layouts are fully visible.

On Macs without a physical notch, the controller draws a pill at the same coordinates.

### Smoke mode

`NOOKIT_SMOKE=1` makes `AppDelegate` instantiate every registered tool view with the environment objects and print a single line, then exit:

```bash
NOOKIT_SMOKE=1 ./build/Nookit.app/Contents/MacOS/Nookit
# NOOKIT_SMOKE rendered=94 missing=
```

`missing=` lists registered views that failed to construct. This catches registry drift and environment-object crashes without UI automation. Run it after any tool change.

## Runtime dependencies

| Feature | Dependency |
| --- | --- |
| Image tools | ImageIO / Core Graphics (system) |
| PDF tools | PDFKit (system) |
| Video/audio tools | AVFoundation (system) |
| Transcribe | Speech framework + Speech Recognition permission |
| Record audio | AVFoundation + Microphone permission |
| Calendar module | EventKit + Calendar permission |
| Wi-Fi name/password | `/usr/sbin/networksetup` / `/usr/bin/security` |
| Zip/unzip | `/usr/bin/ditto` |
| Text to speech | `/usr/bin/say` |
| Keep awake | IOKit power assertions |
| Battery health | `pmset -g batt` and `ioreg` |
| Speed test | Latency plus chunked download and upload against `speed.cloudflare.com`, with an OVH fallback payload |
| AI Chat | Apple Intelligence when available, or any local model through Ollama / an OpenAI-compatible server (`Settings → AI`) |
| Video edit, subtitle, GIF, speed and frame tools | Optional FFmpeg (`brew install ffmpeg`); Apple codecs cover convert, trim, mute and extract audio |
| Streaming-site downloads | Nookit auto-installs the official `yt-dlp` binary into Application Support on first use; a Homebrew/system copy is preferred. Node or Deno enables YouTube's full-quality JavaScript extraction; without one the tool falls back to YouTube's compatible client |
| Office / web / Markdown to PDF | Optional LibreOffice for full fidelity; native XML text-and-table rendering otherwise |
| Display Control | DisplayServices for built-in brightness; DDC/CI over IOAVService for external monitors |
| Mouse Fixes | Accessibility permission plus a CGEvent tap, active while Nookit is open |

The app has no analytics SDK, no crash reporter, no account, and no background upload. Network use is limited to the speed test, Download Video (including the one-time yt-dlp engine download), Web Page to PDF, Apple map tiles/search in Coordinate Picker, a local AI model server you configure, and (in a future licensed build) activation.

## Permissions

`Info.plist` declares microphone, speech recognition, calendar, camera, location, Apple Events, Downloads, Desktop and Documents usage strings. The app requests a permission only when the relevant tool/module is opened; declining leaves the rest of the app usable.

`Core/Permissions.swift` imports AppKit because the permission prompts need the main app to be active.

## Current gaps

- No licence key flow or activation server.
- No auto-update feed.
- No Developer ID signing, hardened runtime, notarization, stapling, or DMG build.
- No app sandbox. Files are accessed through user-selected URLs and standard folder permissions.
- AI Chat uses Apple Intelligence on macOS 26 when available and falls back to a local Ollama or OpenAI-compatible server configured in Settings → AI. It explains which provider is active.
- 14 notch modules remain roadmap entries. They appear with status labels, not fake screens.
- All 94 catalogue tools are implemented, but some call system FFmpeg or LibreOffice; the UI names the missing piece before running. Download Video provisions its own `yt-dlp` on first use.
- Swift 6 concurrency warnings are suppressed by Swift 5 language mode, not fixed.

## Distribution checklist

Do this before offering a public download:

1. Replace the ad-hoc signature with a Developer ID Application certificate.
2. Enable hardened runtime and add only the entitlements the app needs (audio input, Apple Events, user-selected files).
3. Add a licence/activation design that does not collect file data, and a signed auto-update feed.
4. Build and sign a DMG, submit it with `xcrun notarytool submit --wait`, then `xcrun stapler staple`.
5. Verify with `spctl --assess --type execute --verbose` and a clean-machine install.
6. Host the notarized DMG and update the site’s “notarized before release” copy only after this passes.

Until then, the site deliberately says **notarized before release**, and the app is for local development.

## Adding a tool

1. Add or promote the tool in `shared/catalog.mjs` (`implemented: true`).
2. Run `node shared/build-catalog.mjs` from the repo root.
3. Build the SwiftUI screen in the appropriate `Tools/*.swift` file using `ToolPage`/`ToolCard`.
4. Register the slug in `ToolRegistry.registerAll()`.
5. Run `./build-app.sh` and `NOOKIT_SMOKE=1 …`; confirm `rendered` increases and `missing=` is empty.
6. Rebuild the website (`cd web && pnpm build`) so the Ready badge and counts update.

## Xcode path

If you have full Xcode with a matched toolchain, `Package.swift` should resolve as an executable target with the `Resources` folder processed. You will still need to add the app bundle metadata, icon, and signing settings in an Xcode target; the SwiftPM executable alone is not a distributable `.app`.
