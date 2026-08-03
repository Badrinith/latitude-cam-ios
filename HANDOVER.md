# Latitude Cam iOS — Handover

**Status:** Live camera pipeline working on device. 192 tests passing.

**Deployment:** Debug builds install and run on device. Not yet submitted to TestFlight.

---

## Quick Start

```bash
cd ~/latitude-cam-ios/LatitudeCam

# Simulator
xcodebuild build -scheme LatitudeCam -configuration Debug -sdk iphonesimulator -derivedDataPath build
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/LatitudeCam.app
xcrun simctl launch booted com.latitude.cam

# Device
xcodebuild build -scheme LatitudeCam -configuration Debug -destination "id=<device-udid>" -derivedDataPath build
xcrun devicectl device install app --device "<device-udid>" build/Build/Products/Debug-iphoneos/LatitudeCam.app

# Tests
xcodebuild test -scheme LatitudeCam -configuration Debug -destination "id=<simulator-udid>" -derivedDataPath build
```

`xcodebuild test` takes ~90s including the build. Redirect to a file rather than piping through
`grep` — a buffering grep makes the run look hung when it is only slow.

### Debug screen routing

Any screen can be launched directly, which is how the review screenshots were taken:

```bash
SIMCTL_CHILD_LAT_SCREEN=viewfinder SIMCTL_CHILD_LAT_SHEET=pro xcrun simctl launch booted com.latitude.cam
```

`LAT_SCREEN`: `splash` · `onboarding` · `login` · `viewfinder` · `filmsim` · `library` · `edit` · `review` · `settings`
`LAT_SHEET`: `pro` · `export`

---

## Three architectural constraints

These are load-bearing. Each was arrived at by breaking the app first; violating any of them
reproduces a specific failure that took a long time to diagnose.

### 1. Frames are published on their own object

`CameraManager.frames` is a separate `FrameBuffer: ObservableObject` holding only the latest
`UIImage`. `CameraManager` itself publishes only `status`.

**Why:** frames arrive 30×/second. Anything holding `@ObservedObject` on an object that publishes
frames re-evaluates its body 30×/second. An earlier version forced the whole `ViewfinderScreen` to
rebuild per frame (via `.onReceive(objectWillChange)` + `.id(UUID())`), which tore down and
recreated every control mid-gesture. The symptom was *"only the live feed works, every button is
dead"* — the buttons were fine, they were being destroyed between touch-down and touch-up.

**Rule:** anything observing `FrameBuffer` must be a small leaf view. `CameraPreview` and
`LiveHistogramView` are the only two. `LiveHistogramView` owns its own `HistogramSampler`, which
re-publishes at 5Hz, so the histogram's redraws stay inside that leaf too.

### 2. The render pipeline is GPU-only, and the `CIContext` is built once

`CameraManager.render(_:with:)` is a chain of `CIFilter`s: white balance → exposure → film matrix →
halation → vignette → grain → focus peaking.

**Why:** the original film profiles ran per-pixel in Swift (`convertToPixels` allocating a `Pixel`
struct per pixel, ~2M per frame) and `CIContext()` was constructed inside `captureOutput`. Together
these produced roughly five seconds between frames.

**Rule:** no per-pixel Swift loops and no `CIContext()` on the frame path. The per-pixel
implementations in `FilmProfiles.swift` / `ExposureControl.swift` remain as the *reference* the
tests assert against — `FilmMatrixTests` pins the GPU matrices to them so the two cannot drift.

**Gotcha:** CoreImage works in linear light, so the GPU result is not numerically identical to the
sRGB byte multiply in `FilmProfiles`. Tests assert direction and equality-of-channels, not exact
values. Do not "fix" this by asserting exact equality.

### 3. Settings live in `UserDefaults`, not on `AppState`

`Pref` (Theme.swift) holds the keys. The Settings screen binds with `@AppStorage`; the viewfinder,
render pipeline and gallery read the same keys directly.

**Why:** grid style, aspect ratio, JPEG quality, peaking colour, histogram style and haptic strength
are each read by a different subsystem. Threading them through the view tree would have meant
passing six values through four screens.

---

## Project structure

```
LatitudeCam/Sources/
├── UI/
│   ├── Theme.swift              Design tokens, Pref (settings keys), AppState, UIImage crop helper
│   ├── Components.swift         Glass chrome, CompositionGrid, SliderRow, DialRow, FilmRing,
│   │                            ShutterButton, chips, BottomSheet
│   ├── Haptics.swift            The whole haptic vocabulary + strength levels
│   ├── SplashScreen.swift       Cold-launch sequence: SplashDirector, IrisAperture, glyphs
│   ├── EntryScreens.swift       Onboarding, Login
│   ├── ViewfinderScreen.swift   Camera screen, HUD, aspect mask, Pro sheet
│   ├── LibraryScreens.swift     Film Sim, Library grid, Edit screen + PhotoEditor
│   └── ReviewSettingsScreens.swift  Review, ShareSheet, Export sheet, Settings
├── CameraManager.swift          Capture session, FrameBuffer, RenderSettings, GPU pipeline
├── HistogramEngine.swift        Per-pixel reference + HistogramSampler (CIAreaHistogram, 5Hz)
├── PhotoGallery.swift           Disk-backed roll; shoot settings encoded in the filename
├── FilmProfiles.swift           Pixel + the four film transforms (reference implementation)
├── ExposureControl.swift        ISO/shutter multipliers (reference implementation)
├── PreviewEngine.swift          Legacy offline pipeline — not on the live path
├── PhotoExporter.swift          File export helpers
├── AdvancedFeatures.swift       Focus peaking maths, batch processor, custom profiles
└── ProductionFeatures.swift     PermissionManager, error handling, memory helpers
```

---

## What each control actually does

Every control listed here is wired end to end. `AppStateWiringTests` asserts the link for each one —
a control that renders but is not connected fails there.

| Control | Effect |
|---|---|
| Film ring (viewfinder) | `CIColorMatrix`, live |
| Intensity | blends identity ↔ film matrix |
| Shutter, ISO | `setExposureModeCustom` on the real sensor, clamped to the device's supported range; falls back to simulated EV if the hardware refuses |
| White balance | `CITemperatureAndTint`, seven named lighting temperatures |
| Exposure comp. | `CIExposureAdjust`, ±2.5 EV in half stops |
| Grain / halation / vignette | cached noise overlay / `CIBloom` / `CIVignette` |
| Focus peaking | `CIEdges`, tinted by the Settings colour |
| Aspect badge | cycles the ratio, dims the crop, and crops the saved photo |
| Shutter | freezes the frame → Review → Save writes to the roll |
| Grid setting | viewfinder overlay (thirds / golden / off) |
| JPEG quality | `jpegData(compressionQuality:)` on save |
| Haptic strength | changes generator *and* intensity (see below) |

### Manual controls are dials, not sliders

`DialRow` is a knurled barrel with the values engraved on it, turning under a fixed index — an
X-series command dial. A slider can rest anywhere along its track, which is the wrong promise for a
control whose value only ever lands on a stop.

`AppState` stores positions as `0…1` (for persistence and the HUD) and exposes `shutterIndex`,
`isoIndex`, `whiteBalanceIndex`, `exposureIndex` for the dials. `DialIndexTests` asserts the round
trip is lossless — a lossy one would drift a stop every time the sheet reopened.

### Haptics

| Level | Detent | Impacts |
|---|---|---|
| Subtle | `selectionChanged()` | 0.55 |
| Standard | rigid impact | 0.85 |
| **Strong** (default) | rigid impact | 1.0 |

The step from Subtle to Standard changes *generator*, not just amplitude: `UISelectionFeedbackGenerator`
has no intensity parameter and tops out far softer than a rigid impact. A "louder" detent has to be a
different mechanism. At Strong the shutter also fires a second lighter beat 55ms later — a mirror
returning after the exposure.

`Haptics.detent()` must only fire where the value genuinely changes. `HapticsAndDetentTests` walks
500 slider positions asserting click and value change together, in both directions.

---

## Bugs fixed this session

| Bug | Root cause |
|---|---|
| App crashed on launch | `AppState` built two `CameraManager`s — a property initialiser *and* an assignment in `init` |
| Viewfinder showed a black screen | Nested `ObservableObject` not observed; `cameraManager` is a plain `let` on `AppState`, so frame updates never invalidated the view |
| Every control except the live feed was dead | `.id(UUID())` on the screen rebuilt the whole tree 30×/second (see constraint 1) |
| ~5s between frames | Per-pixel Swift film transforms + a `CIContext` per frame (see constraint 2) |
| Capture erased the frame just taken | `PhotoGallery.loadPhotos()` assigned `photos = loaded`, clobbering an in-memory capture that landed before the first disk read finished. Now merges on id. |
| Gallery back button did nothing | Grid cells sized the `Image` directly, so a 1080px photo laid out far larger than its cell. `.clipped()` hides overflow but **hit testing still used the full bounds** — the top row swallowed taps meant for the back button. Fixed with `Color.clear` + `overlay` + `contentShape`. |

---

## Verified vs not

**Verified:** all 192 tests; every screen rendered and inspected via `LAT_SCREEN`; the live camera
feed, film look and capture confirmed on device by the owner.

**Not verified — no Simulator app in this Xcode install, so touches could not be driven:**

- Every haptic cue. Their *wiring* is tested; the sensation is not.
- The film ring and dial drag gestures.
- The splash skip tap.
- The gallery back-button fix — diagnosed from the layout, not by reproducing the tap.

With a working Simulator, `mcp__Claude_Code_iOS_Simulator__control` drives all of these. The Xcode at
`~/Downloads/Apps/Xcode-beta.app` has no `Applications/Simulator.app`, which is why it could not.

---

## Known gaps

| Gap | Note |
|---|---|
| Stills come from the video stream | Capture uses the live 1080p pipeline rather than `AVCapturePhotoOutput`. One proven code path; full-resolution stills would need a second one plus re-applying the look. |
| ProRAW toggle is cosmetic | Labels the Review screen. No DNG is written. |
| "Share…" has no custom activity | Presents the standard `UIActivityViewController` with the `UIImage`. |
| Edit saves a new frame | `PhotoGallery` has no update method; edits are non-destructive by adding. The roll grows with each save. |
| `PreviewEngine` / `AdvancedFeatures` are off the hot path | Still contain main-thread `UIGraphics` and per-pixel loops. Harmless where they sit; do not call them per frame. |
| No front camera | `configureAndStart()` requests the back wide-angle only. |
| Login is decorative | Both buttons and "Skip" all call `completeOnboarding()`. No auth. |

---

## Testing notes

Tests that touch `UserDefaults` or `Documents/Gallery` must clear them in `setUp`. Wipe the gallery
*directory* rather than going through `PhotoGallery` — going through the object races its own async
load and leaves the count unpredictable.

`PhotoGallery` and `AppState` hop to the main queue. To assert after them, enqueue a fulfilled
expectation on the main queue and wait; the main queue is FIFO, so it lands after the work under test.

Adding a test file means editing `LatitudeCam.xcodeproj/project.pbxproj` by hand — this project lists
sources explicitly and does not use synchronised groups. Add a `PBXBuildFile`, a `PBXFileReference`,
and the id to both the group `children` and the target's `files`.

| Suite | Covers |
|---|---|
| `FilmProfileTests` · `ExposureControlTests` | Reference colour maths |
| `CameraIntegrationTests` | Settings surface, GPU pipeline, filter-name resolution |
| `AppStateWiringTests` | Every control → render pipeline |
| `HapticsAndDetentTests` | Detent/value agreement, dial indices, haptic strength |
| `SplashTests` | Sequence timing, skip, cold-launch flow, iris geometry |
| `EditScreenTests` · `SettingsTests` · `LiveHistogramTests` | Editor geometry, preference mapping, histogram |
| `PreviewEngineTests` · `Phase0_4_AllTests` | Legacy pipeline, gallery, permissions |

`testEveryFilterNameResolves` exists because CoreImage returns the input **unchanged** for an unknown
filter name. A typo would present as a dead toggle rather than a build error.

---

## Entry flow

`AppState` starts on `.splash` and nothing routes back to it. `AppState` is constructed once per
process, so the splash cannot replay when the app returns from the background — cold launch only.

The splash hands off via `finishSplash()`: first run goes to onboarding, every run after goes
straight to the viewfinder. `Pref.onboarded` records the difference, set by `completeOnboarding()`.

The sequence runs 8.0s across four features and is skippable by tapping anywhere; a "Tap to skip"
hint fades in after the first beat rather than immediately. Reduced motion skips the machinery and
shows the content statically for 2.4s.

---

## Design system

Tokens are in `Theme.swift` and unchanged from the original handoff.

```
Ink.base   #0D0D0D      Tone.primary #F2EFE8      Accent.amber     #D98A52
Ink.raised #161616      Tone.secondary 55%        Accent.amberDeep #8A5A34
Ink.card   #1C1C1E      Tone.hairline  12%

FilmSwatch  amber #8A7A63 · slate #6B6A63 · rust #9C3F2E · mono #2B2B2B
```

`Font.ui()` is SF Pro for interface text; `Font.mono()` is SF Mono and is reserved for instrument
readouts — shutter, ISO, Kelvin, EV, film names. Keeping that split is what makes the chrome read as
a camera rather than as an app.

Glass chrome is `.ultraThinMaterial` + a 20% black tint + a 10% white hairline. The tint is load
bearing: without it the chrome washes out over a bright camera feed.
