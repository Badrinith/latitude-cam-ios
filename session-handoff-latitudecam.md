# Latitude Cam — Session Handoff

**Date:** 5 Aug 2026
**Branch:** `feat/camera-pipeline-dials-splash` — 25 commits, **all local, nothing pushed to `origin`**
**Tests:** 234 passing
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

PhotoGallery   2048pt in memory, full-res on disk, CGImageSourceCreateThumbnail on load
PhotoExporter  paired asset (.photo + .alternatePhoto), falls back to two assets
```

**UI files:** `Barrel.swift` (Barrel · FilmBarrel · BarrelCluster · DeviceOrientation), `ViewfinderScreen.swift` (single view tree; blocks positioned by `clusterCentre`/`filmCentre`, constant size, rotation + position animate).

**Layout:** pro cluster · lens selector · shutter · film barrel, top to bottom. Lens selector is always visible; the cluster is gated on pro mode. Shutter fixed. Landscape moves the two control bands to the ground-facing edge; the shutter does not move.

## Code state

- `Barrel.swift` is in `project.pbxproj` by hand (`A021`/`B021`) — this project lists sources explicitly.
- Dead but compiled: `FilmKnob.swift`, `RotaryDial.swift`, `ReviewScreen`, `ManualControlsSheet`, `BottomSheet` presentation in `ViewfinderScreen`, `AppState.proRAW`.
- Design mockups in `design/` — `ten-styles.html`, `bottom-dials.html`, `command-dial.html`.
- Not covered by tests: the whole photo-output path (needs hardware).

## Known gaps

1. RAW pairs split into two Photos assets at any aspect but the sensor's own (JPEG cropped, DNG not → `PHPhotosErrorDomain 3300`, falls back to two assets).
2. `proRAW` toggle in the corner rail does nothing — Format chips superseded it.
3. Edit screen writes a new frame rather than replacing; roll grows per save.
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
