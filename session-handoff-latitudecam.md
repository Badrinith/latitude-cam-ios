# Latitude Cam — Session Handoff

**Date:** 5 Aug 2026
**Branch:** `feat/camera-pipeline-dials-splash` — 38 commits, **all local, nothing pushed to `origin`**
**Tests:** 275 passing
**Device:** iPhone 17 Pro Max, UDID `854CD202-7808-597B-A70F-6A6628AED263` (build installed and current)

---

## Key decisions

| Decision | Rationale |
|---|---|
| Stills come from `AVCapturePhotoOutput`, never from `FrameBuffer` | The preview is 1080p; saving it produced 250KB files |
| `sessionPreset = .photo` | Resolution presets cap the photo output too |
| `maxPhotoQualityPrioritization = .quality` set at configuration | A per-capture value above the ceiling raises `NSInvalidArgumentException` |
| One `StillCaptureDelegate` per capture, keyed by `uniqueID` | RAW+processed reports twice; rapid shutter taps overlap |
| DNG is untouched sensor data; JPEG carries the film look | Negative and print of one exposure |
| Roll holds 2048pt copies; masters go to Photos + DNG folder | Full 48MP `UIImage`s in memory emptied the gallery |
| Exposure automatic until a dial leaves `A` | Forced manual (1/240, ISO 100) was the dark-viewfinder cause |
| Pro mode off by default, persisted; leaving it restores auto | Hidden controls must not stay active |
| Barrel replaces rotary dial for all controls | Its shape states the gesture; the dial failed silently |
| App locked to portrait; controls migrate to the ground-facing edge | Picture must not reflow when the body turns |
| Neutral film stock is default, identity matrix | Camera shows the scene before an opinion of it |
| Lenses come from a virtual device + zoom, not input swapping | Changing lens costs a zoom, not a session reconfiguration |
| Lens ladder read from `virtualDeviceSwitchOverVideoZoomFactors` | A 17 Pro Max and an SE disagree about what exists |
| Shutter is a six-blade iris carrying the meter reading | The aperture is already looking at the light; exposure reads without leaving the frame |
| Metering target is 118 (18% grey through sRGB), not 128 | Metering to mid-scale reads a third of a stop hot |
| 11 stocks in 4 families; curves only on the 6 new ones | The 4 originals are pinned to per-pixel references in `FilmProfiles.swift` |
| Film selector is two-tier: family barrel, then stock barrel | 11 long names will not fit one roll; a 12th joins a family rather than lengthening it |
| Library filters by family, not stock | 12 chips in a fixed HStack ran off-screen — that was "out of frame" |
| Gallery holds a 420pt grid copy beside the 1280pt roll copy | A 3-column cell is ~360px; downsampling a megapixel per cell per scroll tick |
| Portrait reconfigures the photo output, on demand only | Depth delivery narrows the device format and costs resolution on every frame |
| Portrait applies on capture, not in the preview | Live depth needs a depth stream; the matte arrives with the still |
| Editor uses the same barrel as the camera | An editor should not be learned separately from the camera it belongs to |
| Apple Photos is the only copy; roll reads back from a "Latitude" album | The app kept its own JPEG of every frame, so each picture existed twice on the phone |
| Shoot settings ride in the asset's `originalFilename` | Metadata survives the round trip without a second store |
| `photoQualityPrioritization = .balanced` per capture | `.speed` gave up processing entirely; `.balanced` + fast-capture-prioritization adapts to shooting pace |
| Pinch zoom drives `zoom` (Double), selector snaps to nearest lens | A pinch lands between marked lenses; the lens buttons name the nearest one |
| Gallery pinch changes column count (2-5), not image scale | Scaling photos in a fixed grid would crop them, not "zoom" the contact sheet |
| Gallery viewer is a `TabView(.page)` over the filtered roll, each page independently pinch/pan zoomable | Paging, momentum, and per-page zoom state all come free from the system |
| Gallery loading is async + incremental, `PhotoGallery` observes `PHPhotoLibraryChangeObserver` | Was synchronous over the whole album with no retry after permission — empty until relaunch |
| Gallery holds grid thumbnails only; full-res fetched on demand via `loadFullImage` | Loading full-res for every asset up front was the "completely broken" symptom |
| Four selectable gallery layouts (`Pref.galleryLayout`): Organizer/Negative/Archive/Storyboard | User-chosen from Settings; `GalleryHost` owns shared filter/viewer state, layouts are dumb renderers |
| Photo viewer presented via `.fullScreenCover(item:)`, not `.overlay` | An overlay sizes to its host view's own frame; a content-hugging layout opened the viewer clipped and small, which also hid Storyboard's close button outside the tappable region |
| Negative/Archive/Storyboard wrapped in their own `ScrollView`; Organizer is not | They had no scroll container at all before — content below the fold was unreachable. Organizer relies on `LibraryScreen`'s outer ScrollView so its pinch-to-resize-columns gesture reads directly off the grid |
| Still-capture rotation read from `AVCaptureDevice.RotationCoordinator`, not a hand-built angle table | Two manual UIDeviceOrientation→angle mappings were both wrong on device; the coordinator computes it from the live device instead of a guess |
| Gallery layouts: Organizer, Contact Roll, Archive, Storyboard, Darkroom | Negative (colour-inverted) replaced with Contact Roll (true colour, same object as the film barrel); Darkroom added |
| Photo viewer's Edit/Delete are a real bottom toolbar, not floating pills over the image | Floating controls competed with the TabView's own swipe-to-page gesture for the same touches |
| Viewer metadata (film, ISO, shutter, timestamp) behind a swipe-up `BottomSheet`, not always-visible | Keeps the image itself the only thing in front of the eye until asked for detail |
| Edit ladders have an odd stop count | Only an odd count puts a notch exactly at neutral |

## Architecture

```
CameraManager
├── AVCaptureVideoDataOutput → FrameBuffer      preview only, 1080p, 30fps
├── AVCapturePhotoOutput     → CapturedStill    everything saved, full resolution
│   └── zero shutter lag · responsive capture · fast capture prioritization
├── render(CIImage)          GPU CIFilter chain, focusPeaking excluded from stills
├── mirroredForFrontCamera   front mirror in render space, not on the connection
└── orient(connection:front:) back 90° · front 0°

AppState  ──syncCamera()──▶  RenderSettings  ──apply()──▶  CameraManager
   proMode · autoExposure · autoFocus · metering · pointOfInterest

PhotoGallery   1280pt roll + 420pt grid copy in memory; loads from the Latitude album in Photos
PhotoExporter  paired asset (.photo + .alternatePhoto), falls back to two assets
```

**UI files:** `Barrel.swift` (Barrel · FilmBarrel · BarrelCluster · DeviceOrientation), `ViewfinderScreen.swift` (single view tree; blocks positioned by `clusterCentre`/`filmCentre`, constant size, rotation + position animate).

**Layout:** pro cluster · shutter row · two-tier film selector. Shutter row is `PRO · lens selector · [release] · roll`, release centred in its own layer so nothing beside it shifts it. Cluster gated on pro mode. Landscape moves the two control bands to the ground-facing edge; the shutter does not move.

## Code state

- `Barrel.swift` is in `project.pbxproj` by hand (`A021`/`B021`) — this project lists sources explicitly.
- Dead but compiled: `FilmKnob.swift`, `RotaryDial.swift`, `ReviewScreen`, `ManualControlsSheet`, `BottomSheet` presentation in `ViewfinderScreen`, `AppState.proRAW`, `BackLink`, `SliderRow` (editor now uses barrels).
- Design mockups in `design/` — `ten-styles.html`, `bottom-dials.html`, `command-dial.html`.
- Not covered by tests: the whole photo-output path (needs hardware).

## Known gaps

1. RAW pairs split into two Photos assets at any aspect but the sensor's own (JPEG cropped, DNG not → `PHPhotosErrorDomain 3300`, falls back to two assets).
2. `AppState.proRAW` is now read only by the unreachable `ReviewScreen`; the button is gone.
3. Edit screen writes a new frame rather than replacing; roll grows per save.
5. `FilmPreviewBuffer` is never filled now — `FilmKnob` is its only reader and is dead.
4. No Simulator.app in this Xcode (`~/Downloads/Apps/Xcode-beta.app`) — device verification only.

## Next steps

1. **Verify on device:** tap-to-meter reticle lands under the thumb (axes are swapped for the 90° preview rotation); landscape controls reach the correct edge; PRO toggle round-trips to auto.
2. **Delete dead code:** `FilmKnob.swift`, `RotaryDial.swift`, `proRAW` toggle, unreachable `ReviewScreen`/`ManualControlsSheet`/`BottomSheet` — then drop `A019`/`B019`, `A020`/`B020` from `project.pbxproj`.
3. **Decide RAW pairing:** either stop cropping the JPEG when RAW is on, or crop the DNG. Both change what the aspect badge promises.
4. **Update `HANDOVER.md`** — still documents the rotary dial and the bottom sheet as current.
5. **Push the branch** if the work is to leave this machine.

## Commands

```bash
cd ~/latitude-cam-ios/LatitudeCam

xcodebuild build -scheme LatitudeCam -configuration Debug \
  -destination "id=854CD202-7808-597B-A70F-6A6628AED263" -derivedDataPath build

xcrun devicectl device install app --device "854CD202-7808-597B-A70F-6A6628AED263" \
  build/Build/Products/Debug-iphoneos/LatitudeCam.app

xcodebuild test -scheme LatitudeCam -configuration Debug \
  -destination "id=0C1D93ED-BD2C-4E9D-A4D4-ADCB639CF332"
```

Tests need a concrete simulator UDID; `generic/platform=iOS Simulator` is rejected. `xcodebuild` must run from `LatitudeCam/`, not the repo root.

## Latest session (commit `4acf481`)

Three user-reported bugs, each root-caused before touching code (per systematic-debugging — two prior rotation attempts had failed by guessing at the angle instead):

1. **Landscape capture still rotated**, third report. Root cause: `CameraManager.captureStill`'s `StillCaptureDelegate` decodes the processed photo with `CIImage(data: processed)` — this silently drops EXIF orientation unless told to apply it. The `AVCaptureConnection.videoRotationAngle` set right before capture (`CameraManager.swift` ~line 790) was actually writing correct orientation into the file the whole time; both earlier fixes (hand-built angle table, then `RotationCoordinator`) changed *that* line and could never have worked, because the very next step throws the result away. Fix: `CIImage(data: processed, options: [.applyOrientationProperty: true])`. One line, once the actual pipeline was traced.
2. **Swipe-up-for-metadata not registering.** It was a `DragGesture`/`.simultaneousGesture` on `ZoomableImage`, which lives inside `TabView(selection:)`. TabView(.page)'s own paging pan gesture is a `UIScrollView` under the hood, outside SwiftUI's gesture arena, and routinely wins the touch regardless of `.simultaneousGesture`. Moved the swipe+tap handler onto the "SWIPE UP FOR DETAILS" row in `PhotoViewer`, which is a sibling of the TabView, not a descendant — no more gesture to compete with.
3. **Gallery slow to populate.** `PhotoGallery.loadPhotos()`'s grid-thumbnail `PHImageRequestOptions` had `isNetworkAccessAllowed = true`, so every thumbnail — even for photos this app just captured and that are almost always already local — queued behind an iCloud availability check. Set to `false` for the grid pass only; `loadFullImage(for:)` (full-res, on open) correctly keeps it `true`.

**Verification limits, stated plainly:** builds succeeded, all 275 tests pass, install to device UDID `854CD202-7808-597B-A70F-6A6628AED263` succeeded. None of that is the same as watching the camera take a landscape photo or timing the gallery — there is no tool available in this environment that operates the phone's camera or observes rendered UI on-device. All three fixes are argued from tracing the actual code path to a concrete, demonstrable defect, not from re-guessing at symptoms, but they are unverified on hardware until the user confirms.
