# Latitude Cam iOS - Phase 0

Native iOS app built with Swift/SwiftUI and TDD.

## Setup

1. **Install Xcode 16+** (iOS 17+)
2. **Open in Xcode:** `open ~/latitude-cam-ios` (we'll create .xcodeproj)
3. **Run tests:** Cmd+U in Xcode

## Architecture

```
LatitudeCam/
├── Core/
│   ├── FilmProfiles/     ← Image processing tests first
│   ├── Camera/           ← Camera capture
│   ├── Exposure/         ← Manual controls
│   └── Export/           ← Save functionality
├── UI/
│   ├── Camera/
│   ├── Controls/
│   └── Preview/
└── Tests/
    └── Unit/
        ├── FilmProfilesTests
        ├── CameraTests
        ├── ExposureTests
        └── ExportTests
```

## TDD Process

**Phase 0.1: Film Profiles** (Core image processing)
- Write failing test
- Implement minimal code
- Refactor

**Phase 0.2: Exposure Control** (Manual settings)
- ISO adjustment
- Shutter speed

**Phase 0.3: Camera Integration** (Real capture)
- Phone camera capture
- Real-time preview

**Phase 0.4: UI & Export** (User interface)
- Film applied to photos
- Save/export

## Run Tests

```bash
cd ~/latitude-cam-ios
# We'll run via Xcode or swift test once properly configured
```

## Status

- Phase 0.1: In Progress (Film Profiles - RED)
- Phase 0.2: Planned
- Phase 0.3: Planned
- Phase 0.4: Planned
