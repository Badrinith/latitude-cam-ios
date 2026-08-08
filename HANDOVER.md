# Latitude Cam iOS — Handover

**Status:** Live camera pipeline and full-resolution RAW capture working on device.
351 tests passing. Currently on build **1.0.1 (40)**.

**Deployment:** Debug builds install and run on device. Not yet submitted to TestFlight.

**Branch:** `feat/camera-pipeline-dials-splash` — **68 commits ahead of `origin/main`, none pushed.**
The remote has only `main`, and that commit is already contained in this branch. All of this work
exists on one machine; pushing is the single highest-value thing an incoming maintainer can do.

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

## Four architectural constraints

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

### 3. The viewfinder and the photograph are two different capture paths

`AVCaptureVideoDataOutput` feeds the preview. `AVCapturePhotoOutput` produces
everything that gets saved. They are not interchangeable.

**Why:** stills used to be lifted out of the preview stream — `capturePhoto()`
returned `frames.image`. That stream is 1080p, so every saved file was 2MP and
about 250KB, and no JPEG quality setting could change it. The size looked like a
compression bug for several rounds; it was the source that was wrong.

**Rule:** nothing saved to the roll, to Photos, or to disk may come from
`FrameBuffer`. The preview is a viewfinder.

Three things about the photo output are load-bearing, each set during
`configureAndStart`:

- `sessionPreset` must be `.photo`. A resolution preset such as `.hd1920x1080`
  caps the *photo* output too, so full-resolution stills are impossible under it.
- `maxPhotoQualityPrioritization` must be raised to `.quality` before any capture
  sets `photoQualityPrioritization = .quality`. AVFoundation does not clamp a
  per-capture value above the ceiling — it raises `NSInvalidArgumentException`.
  This crashed the shutter on every press.
- Zero shutter lag, responsive capture and fast capture prioritization are all
  enabled. Responsive capture is why the develop step must not run on
  AVFoundation's callback queue.

Focus peaking is excluded from the still render. It is a viewfinder aid and has
no business in a saved photograph.

### 4. Settings live in `UserDefaults`, not on `AppState`

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
│   ├── ViewfinderScreen.swift   Camera screen, HUD, aspect mask, Pro sheet, control-style routing
│   ├── ViewfinderControls.swift KnobMath, Knob, Bellows Drawer, Crown, the Top Plate deck
│   │                            (PlateDial · DialBarrel · FilmCardStack · PlateLensRow),
│   │                            LeafShutterButton + LeafShutterGeometry, DevelopingOverlay
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
| Shutter | full-resolution sensor capture → roll + Photos, staying on the viewfinder |
| Format (Pro sheet) | RAW Only · JPEG Only · RAW + JPEG |
| Resolution (Pro sheet) | 4/8/12MP or Full, matched to the nearest `supportedMaxPhotoDimensions` |
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
| Landscape photos came out rotated | Four attempts. The first three all went through AVFoundation's connection angle and EXIF, and the third revealed why none could work: `CIImage(data:)` silently discards EXIF orientation unless `.applyOrientationProperty` is set, so the correctly-rotated buffer was decoded back to sensor orientation on every capture. Current build bakes rotation into the pixels from the same `DeviceOrientation` angle that drives the UI. |
| ISO and shutter dials did nothing | They wrote `app.iso`/`app.shutter` directly while auto-exposure was still on, so the camera ignored them and the readouts kept saying `AUTO`/`ISO A`. The classic barrels already dropped out of A in their index setters; the plate's dials bypassed that path. Touching either dial now leaves A. |
| Landscape controls stopped responding | The film strip was appended to a `VStack` that had already consumed the full height, so it overflowed and pushed the shutter row off-screen. Now an overlay — an overlay cannot push what it sits over. |
| Landscape bands overlapped the plate and the shutter | `.top`/`.bottom` are not the sky and ground edges when the body is turned, and a band measured against the *screen* is the whole screen tall. Bands are now placed by physical edge inside a `viewfinderRegion` bounded by the plate and the release. |
| Rotated switch labels clipped to "PORTI", "GR", "3:" | A rotated word needs its width in the frame's height. Switches are 54pt squares with glyphs now. |
| Gallery delete removed nothing | `deletePhotos` derives Photos asset ids and bails when there are none, but `addPhoto` creates frames with `assetID: nil` until the roll reloads. Correct behaviour — an unmirrored frame has nothing to delete — but the tests were written against the old immediate-removal contract and had to be rewritten, not forced back. |
| Gallery back button did nothing | Grid cells sized the `Image` directly, so a 1080px photo laid out far larger than its cell. `.clipped()` hides overflow but **hit testing still used the full bounds** — the top row swallowed taps meant for the back button. Fixed with `Color.clear` + `overlay` + `contentShape`. |

---

## Verified vs not

**Verified:** all 351 tests; every screen rendered and inspected via `LAT_SCREEN`; the live camera
feed, film look, and RAW + JPEG capture reaching Apple Photos, all confirmed on device by the owner.

**A note on how this session went, because it matters for the next one.** Several bugs took three or
four attempts because they were verified by screenshot rather than by test: landscape geometry and
capture rotation especially. The pattern that finally worked was to extract the arithmetic into a
pure type — `KnobMath`, `LeafShutterGeometry`, `skyEdge`, `viewfinderRegion` — and pin it. Layout and
orientation bugs are invisible in code and obvious on glass; if you find yourself guessing at a
constant, that is the signal to make it testable instead of trying another value.

**Not covered by tests:** the whole photo-output path. `AVCapturePhotoOutput` needs real hardware,
so `.photo` preset, the quality-prioritization ceiling, RAW availability and the Photos pairing are
all device-verified only. The four faults behind "the files are 250KB" and "the shutter crashes"
would each have been caught by a test that could run — none can.

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
| RAW pairs split in two on a cropped aspect | The developed JPEG is cropped to the chosen aspect, the DNG keeps the full sensor frame, so Photos rejects the pairing (`PHPhotosErrorDomain` 3300, `changeNotSupported`) and `saveCapture` falls back to two assets. At the sensor's own aspect they merge into one ProRAW-style asset. Fixing it properly means either not cropping the JPEG when RAW is on, or cropping the DNG — both change a promise the aspect badge makes. |
| Review screen is unreachable | Capture goes straight back to the viewfinder. `ReviewScreen`, `deleteCapture()` and `mirrorCaptureToPhotos()` are still built and still tested, but nothing routes to them. |
| ProRAW toggle in the Pro sheet does nothing | RAW is driven by the Format chips. The toggle predates them and should be removed. |
| "Share…" has no custom activity | Presents the standard `UIActivityViewController` with the `UIImage`. |
| ~~Edit saves a new frame~~ | **Fixed.** Edits now go onto the asset itself via PhotoKit adjustment data — see *Editing in place* below. |
| `PreviewEngine` / `AdvancedFeatures` are off the hot path | Still contain main-thread `UIGraphics` and per-pixel loops. Harmless where they sit; do not call them per frame. |
| ~~No front camera~~ | **Fixed.** The front camera is a focal length in the lens row, past a divider — `camera.lenses` republishes on flip so the row only ever offers lengths that camera has. |
| Landscape is faked, not real | The app stays portrait-locked: the camera preview is rotated 90° into portrait and the release must not move. Controls reposition themselves to the physically-correct edges instead. Three separate bugs came out of this (see below); if a fourth appears, the alternative is supporting real landscape interface orientation, which is a much larger change. |
| Login is decorative | Both buttons and "Skip" all call `completeOnboarding()`. No auth. |

---

## Viewfinder control styles

The viewfinder has four selectable presentations, chosen in **Settings → Viewfinder → Controls**
(`Pref.viewfinderControls`). They differ only in how the *settings* around the camera are arranged —
every style keeps the release, the roll, PRO and the lens selector, because those are how the camera
is operated at all.

| Style | Shape |
|---|---|
| **Film Label** (default) | The original barrel deck. Nothing changes for an existing user unless they opt in. |
| **Bellows Drawer** | A leatherette drawer under the shutter row holding ISO/shutter/WB knobs. Stows to its pleats, which double as the handle. Closes on flick *velocity*, not distance. |
| **Crown** | One knurled crown on the right edge. Roll to adjust, tap to cycle target, retires after 3.5s. Rolling works whether or not the panel is showing — the panel reports, it is not a prerequisite. |
| **Top Plate** | The design handoff's screen: a 222pt metal plate with five knurled dials, a film-card carousel and a glass HUD. |

**Top Plate is structurally different from the other three.** It replaces the chrome outright rather
than hanging a deck beneath it, so it is the only style that insets the picture — the plate is opaque
and the frame starts below it. `TopPlateBand.height(proOpen:)` is the single source for both the band
and that inset; if they ever disagree the frame slides under metal and tap-to-meter lands off the
thumb. Pinned by test.

- **PRO opens the plate.** With PRO off there are no dials at all: the camera is on auto and every
  dial would read `AUTO`, and a control displaying a value it is not setting is worse than none.
  PRO on drops the five dials and a reset beside them.
- **Turning a dial drops a barrel.** A 44pt dial is good to grab and poor to land a value with, so
  `DialBarrel` slides out with real travel and detents, and is itself draggable (260pt covers the
  ladder). It carries an `ActiveDial.Key` so scrubbing writes back to the right control.
- **Shutter and ISO leave auto when touched**, the way the ring on a real body does. Aperture, WB
  and EV deliberately do not — dragging the camera out of auto as a side effect of nudging white
  balance would be a worse bug than the one that fixed.
- **Landscape repositions rather than rotates.** `skyEdge` is the opposite of the ground edge
  `DeviceOrientation` reports; bands are laid inside `viewfinderRegion`, bounded by the plate above
  and the release below.

`KnobMath` and `LeafShutterGeometry` are pure enums for exactly one reason: a knob that runs
backwards, or blades that fail to meet at full closure, look fine on the page and broken in the hand.

---

## Editing in place

Saving an edit used to call `gallery.addPhoto`, filing a *second* frame beside the first — the roll
grew by one per save and Apple Photos never heard about it. The asset is now edited through the same
adjustment-data mechanism Photos' own editor uses.

| Method | Does |
|---|---|
| `applyEdit(to:image:filmID:)` | Requests `PHContentEditingInput`, writes the rendered JPEG to `output.renderedContentURL`, attaches `PHAdjustmentData` stamped `com.latitude.cam.edit` / `1.0`, commits via `PHAssetChangeRequest.contentEditingOutput`. |
| `revertEdit(_:)` | `revertAssetContentToOriginal()`. Photos still holds the original, so this discards the edit rather than reconstructing anything — and it survives quitting the app. |
| `hasEdit(_:)` | Asks Photos whether the asset carries adjustment data. Asked rather than remembered, because the user can also edit or revert in Photos itself. Drives whether the editor offers **Revert**. |

**`options.canHandleAdjustmentData` returning true for our own identifier is load-bearing.** Without
it, Photos treats a previously-edited frame as un-editable and hands back the *rendered* result as
though it were the original — a second edit stacks on the first and Revert undoes only half.

`DevelopingOverlay` covers the write: the print comes up desaturated with a soft amber line sweeping
down it, then settles into a checkmark. The write is genuinely not instant (Photos renders and swaps),
and a save that shows nothing reads as a tap that missed.

**Device-only.** Everything past the "frame has no asset" guard needs a real photo library. Tests
cover the identifier contract, both not-yet-in-Photos failure paths, and that editing still writes
nothing into app storage — the single-copy invariant. Whether an edit lands in Photos, and whether
Revert restores it, has to be checked on the phone. **Untested on RAW**: how adjustments interact
with a DNG/JPEG pair is unknown.

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
| `PreviewEngineTests` · `Phase0_4_AllTests` | Legacy pipeline, gallery, permissions, in-place editing |
| `KnobMathTests` · `LeafShutterGeometryTests` | Knob direction, ends, seam crossing, detents; blade closure and overlap |
| `ViewfinderControlStyleTests` · `TopPlateCollapseTests` · `PlateSwitchTests` | Style list and default, plate open/closed heights vs the picture inset, switch sizing |
| `LandscapeEdgeTests` · `ViewfinderRegionTests` | Sky/ground edge arithmetic; bands staying inside the picture |
| `DialEngagesExposureTests` | Shutter and ISO leaving auto; the other dials not disturbing it |
| `CaptureExifOrientationTests` | The orientation tag written for each capture rotation |

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
