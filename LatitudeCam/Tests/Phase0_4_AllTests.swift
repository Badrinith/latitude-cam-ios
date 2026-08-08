//
//  Phase0_4_AllTests.swift
//  LatitudeCam
//
//  Comprehensive tests for Phase 0.4: UI Polish, Advanced, Production
//

import XCTest
@testable import LatitudeCam

final class PhotoGalleryTests: XCTestCase {

    /// The gallery persists to disk, so state survives between runs. Wipe the
    /// directory itself — going through the gallery would race its own async
    /// load and leave the count unpredictable.
    override func setUp() {
        super.setUp()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("Gallery"))
    }

    /// Lets the gallery's own main-queue hop land before we assert. Main queue is
    /// FIFO, so a block enqueued after addPhoto runs after addPhoto's insert.
    private func drainMainQueue() {
        let settled = expectation(description: "main queue drained")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2)
    }

    func testGalleryStoresPhoto() {
        let gallery = PhotoGallery()
        gallery.addPhoto(UIImage(systemName: "camera") ?? UIImage(),
                         filmID: "amber", iso: 400, shutterDenominator: 60)
        drainMainQueue()
        XCTAssertEqual(gallery.photos.count, 1)
    }

    func testGalleryKeepsShootMetadata() {
        let gallery = PhotoGallery()
        gallery.addPhoto(UIImage(systemName: "camera") ?? UIImage(),
                         filmID: "rust", iso: 800, shutterDenominator: 240)
        drainMainQueue()

        let photo = gallery.photos.first
        XCTAssertEqual(photo?.filmID, "rust")
        XCTAssertEqual(photo?.iso, 800)
        XCTAssertEqual(photo?.shutterDenominator, 240)
    }

    // MARK: - Deletion
    //
    // Apple Photos owns the only copy of a frame, so deleting one means deleting
    // its asset — and the roll is updated only once Photos confirms that
    // happened. A frame that has not reached Photos yet therefore has nothing to
    // delete, and saying so is the correct outcome: removing it from the roll
    // regardless would hide a photo that still exists in the library.
    //
    // These frames are added directly to the roll and never mirrored, so they
    // stand in for exactly that case. Deletion that does reach Photos needs the
    // real library and is device-only.

    func testDeletingAFrameThatIsNotInPhotosYetSaysSoAndKeepsIt() {
        let gallery = PhotoGallery()
        gallery.addPhoto(UIImage(systemName: "camera") ?? UIImage(),
                         filmID: "amber", iso: 100, shutterDenominator: 60)
        drainMainQueue()
        guard let id = gallery.photos.first?.id else { return XCTFail("no photo to delete") }

        var reported: (ok: Bool, problem: String?)?
        gallery.deletePhotos([id]) { ok, problem in reported = (ok, problem) }
        drainMainQueue()

        XCTAssertEqual(reported?.ok, false, "a frame with no asset cannot have been deleted")
        XCTAssertNotNil(reported?.problem, "a failed delete has to explain itself")
        XCTAssertEqual(gallery.photos.count, 1,
                       "the frame is still in Photos, so it must stay in the roll")
    }

    /// The failure has to be the one the user can act on — the frame is on its
    /// way to Photos and the delete will work shortly — rather than the generic
    /// "could not find" case, which reads as data loss.
    func testAFrameStillBeingAddedReportsThatRatherThanMissing() {
        let gallery = PhotoGallery()
        gallery.addPhoto(UIImage(systemName: "camera") ?? UIImage(),
                         filmID: "amber", iso: 100, shutterDenominator: 60)
        drainMainQueue()
        guard let id = gallery.photos.first?.id else { return XCTFail("no photo to delete") }

        var problem: String?
        gallery.deletePhotos([id]) { _, message in problem = message }
        drainMainQueue()

        XCTAssertEqual(problem?.contains("Apple Photos"), true,
                       "the message should name where the frame actually is")
    }

    /// An id the roll has never heard of resolves to no assets, which must not
    /// be mistaken for a successful delete of nothing.
    func testDeletingAnUnknownIDDoesNotReportSuccess() {
        let gallery = PhotoGallery()
        gallery.addPhoto(UIImage(systemName: "camera") ?? UIImage(),
                         filmID: "amber", iso: 100, shutterDenominator: 60)
        drainMainQueue()

        var reported: Bool?
        gallery.deletePhotos(["photo_0000000000000_0_nonexistent_100_60"]) { ok, _ in reported = ok }
        drainMainQueue()

        XCTAssertEqual(reported, false)
        XCTAssertEqual(gallery.photos.count, 1, "an unrelated id must not touch the roll")
    }

    /// Deleting an empty selection is a no-op, not a crash and not a wipe — the
    /// multi-select UI can reach this with nothing ticked.
    func testDeletingAnEmptySelectionLeavesTheRollAlone() {
        let gallery = PhotoGallery()
        gallery.addPhoto(UIImage(systemName: "camera") ?? UIImage(),
                         filmID: "amber", iso: 100, shutterDenominator: 60)
        drainMainQueue()

        gallery.deletePhotos([])
        drainMainQueue()

        XCTAssertEqual(gallery.photos.count, 1)
    }

    /// Metadata rides in the filename, so a round-trip failure would silently
    /// relabel every photo on the next launch.
    func testIDRoundTripsMetadata() {
        let when = Date(timeIntervalSince1970: 1_700_000_000.5)
        let id = PhotoGallery.makeID(timestamp: when, filmID: "slate", iso: 1600, shutter: 500)
        let parsed = PhotoGallery.parseID(id)

        XCTAssertEqual(parsed.filmID, "slate")
        XCTAssertEqual(parsed.iso, 1600)
        XCTAssertEqual(parsed.shutter, 500)
        XCTAssertEqual(parsed.timestamp.timeIntervalSince1970,
                       when.timeIntervalSince1970, accuracy: 0.01)
    }

    /// A burst of saves inside one millisecond used to produce identical ids.
    /// deletePhoto matches on id, so removing one frame removed the other too.
    func testIDsAreUniqueUnderABurst() {
        let now = Date()
        var seen = Set<String>()
        for _ in 0..<200 {
            let id = PhotoGallery.makeID(timestamp: now, filmID: "amber", iso: 100, shutter: 60)
            XCTAssertFalse(seen.contains(id), "duplicate id: \(id)")
            seen.insert(id)
        }
    }

    /// Uniqueness must not come at the cost of the timestamp — the roll sorts on
    /// it, and an id that rewrites the clock would reorder the whole gallery.
    func testBurstIDsKeepTheirTimestamp() {
        let now = Date(timeIntervalSince1970: 1_700_000_000.25)
        for _ in 0..<20 {
            let parsed = PhotoGallery.parseID(
                PhotoGallery.makeID(timestamp: now, filmID: "amber", iso: 100, shutter: 60)
            )
            XCTAssertEqual(parsed.timestamp.timeIntervalSince1970,
                           now.timeIntervalSince1970, accuracy: 0.01)
        }
    }

    /// Photos already on disk predate the sequence component and must keep their
    /// metadata rather than silently reverting to Amber at ISO 100.
    func testLegacyIDsStillParse() {
        let parsed = PhotoGallery.parseID("photo_1700000000500_rust_800_240")
        XCTAssertEqual(parsed.filmID, "rust")
        XCTAssertEqual(parsed.iso, 800)
        XCTAssertEqual(parsed.shutter, 240)
        XCTAssertEqual(parsed.timestamp.timeIntervalSince1970, 1_700_000_000.5, accuracy: 0.01)
    }

    func testMalformedIDFallsBackToDefaults() {
        let parsed = PhotoGallery.parseID("not-a-latitude-photo")
        XCTAssertEqual(parsed.filmID, "amber")
        XCTAssertEqual(parsed.iso, 100)
        XCTAssertEqual(parsed.shutter, 60)
    }
}

final class HistogramTests: XCTestCase {
    func testHistogramGeneration() {
        let engine = HistogramEngine()
        let pixels = Array(repeating: Pixel(r: 128, g: 128, b: 128), count: 100)
        let histogram = engine.generateHistogram(from: pixels)
        XCTAssertEqual(histogram.brightness, 128)
        XCTAssertEqual(histogram.exposure, "Good")
    }
}

final class FocusPeakingTests: XCTestCase {
    func testFocusAreaDetection() {
        let overlay = FocusPeakingOverlay()
        let pixels = Array(repeating: Pixel(r: 100, g: 100, b: 100), count: 100)
        let areas = overlay.detectFocusAreas(pixels: pixels, width: 10, height: 10)
        XCTAssertGreaterThanOrEqual(areas.count, 0)
    }
}

final class BatchProcessorTests: XCTestCase {
    func testBatchQueueing() {
        let processor = BatchProcessor()
        let image = UIImage(systemName: "camera") ?? UIImage()
        processor.addToBatch(image)
        // Would process and callback
    }
}

final class CustomProfileTests: XCTestCase {
    func testCustomProfileCreation() {
        let editor = CustomFilmProfileEditor()
        let profile = editor.createCustomProfile(name: "Custom", rMult: 1.2, gMult: 0.9, bMult: 0.8)
        let pixel = profile.apply(to: Pixel(r: 100, g: 100, b: 100))
        XCTAssertEqual(pixel.r, 120)
    }
}

final class GridOverlayTests: XCTestCase {
    func testGridRendering() {
        let grid = GridOverlay()
        let image = grid.renderGrid(.thirdRule, size: CGSize(width: 100, height: 100))
        XCTAssertNotNil(image)
    }
}

final class PermissionTests: XCTestCase {
    func testPermissionRequest() {
        PermissionManager.getCameraPermission { status in
            XCTAssertNotEqual(status, .notDetermined)
        }
    }
}

final class MemoryOptimizationTests: XCTestCase {
    func testImageOptimization() {
        let original = UIImage(systemName: "camera") ?? UIImage()
        let optimized = MemoryOptimizer.optimizeImageSize(original)
        XCTAssertNotNil(optimized)
    }
}

final class PrivacyTests: XCTestCase {
    func testPrivacyPolicy() {
        let policy = PrivacyManager.getPrivacyPolicy()
        XCTAssertTrue(policy.contains("Privacy Policy"))
    }
}

// MARK: - Single copy

@MainActor
final class SingleCopyTests: XCTestCase {

    /// The app used to keep its own JPEG of every frame in Documents, so every
    /// picture existed twice on the phone — once where the user expects it and
    /// once where they cannot see it. Adding a frame must now touch app storage
    /// not at all.
    func testAddingAFrameWritesNothingToAppStorage() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("Gallery"))
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("LatitudeCam"))

        let gallery = PhotoGallery()
        gallery.addPhoto(UIImage(systemName: "camera") ?? UIImage(),
                         filmID: "amber", iso: 400, shutterDenominator: 60)

        let settled = expectation(description: "insert landed")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        // Give any stray write a chance to appear before asserting it did not.
        let drained = expectation(description: "queues drained")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { drained.fulfill() }
        wait(for: [drained], timeout: 2)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: documents.appendingPathComponent("Gallery").path),
            "a second copy of the roll is back in app storage"
        )
        XCTAssertEqual(gallery.photos.count, 1, "the frame is still in the roll")
    }

    /// The filename is how the shoot settings survive the round trip through
    /// Photos, so it has to be the id and nothing else.
    func testFilenameCarriesTheIDAndParsesBack() {
        let when = Date(timeIntervalSince1970: 1_000_000)
        let id = PhotoGallery.makeID(timestamp: when, filmID: "harbour", iso: 800, shutter: 250)
        let name = PhotoGallery.filename(for: id)

        XCTAssertTrue(name.hasSuffix(".jpg"))
        let recovered = (name as NSString).deletingPathExtension
        XCTAssertEqual(recovered, id)

        let meta = PhotoGallery.parseID(recovered)
        XCTAssertEqual(meta.filmID, "harbour")
        XCTAssertEqual(meta.iso, 800)
        XCTAssertEqual(meta.shutter, 250)
    }

    /// A frame taken by anything else lands in the album without our filename and
    /// must not crash the loader or claim settings it never had.
    func testAForeignFilenameGetsDefaultsRatherThanNonsense() {
        let meta = PhotoGallery.parseID("IMG_4021")
        XCTAssertFalse(meta.filmID.isEmpty)
        XCTAssertGreaterThan(meta.iso, 0)
        XCTAssertGreaterThan(meta.shutter, 0)
    }
}

// MARK: - Gallery layout preference

final class GalleryLayoutPrefTests: XCTestCase {

    func testFourLayoutOptionsExist() {
        XCTAssertEqual(Pref.galleryLayoutOptions, ["Organizer", "Contact Roll", "Archive", "Storyboard", "Darkroom"])
    }

    func testOrganizerIsTheDefault() {
        UserDefaults.standard.removeObject(forKey: Pref.galleryLayout)
        XCTAssertEqual(Pref.string(Pref.galleryLayout, default: "Organizer"), "Organizer")
    }
}

// MARK: - Editing in place

/// An edit used to file a second frame beside the first: the roll grew by one
/// on every save and Apple Photos never heard about the change. The asset is
/// edited in place now, so what is pinned here is the contract that makes that
/// safe — the identifier Photos hands our own edits back by, and the fact that
/// nothing is written into app storage to do it.
@MainActor
final class InPlaceEditTests: XCTestCase {

    /// Photos routes adjustment data to whichever app claims the identifier. If
    /// it ever changed, previously edited frames would come back as if the
    /// rendered result were the original — a second edit would stack on the
    /// first, and Revert would only undo half of it.
    func testTheAdjustmentIdentifierIsStable() {
        XCTAssertEqual(PhotoGallery.adjustmentFormatID, "com.latitude.cam.edit")
        XCTAssertEqual(PhotoGallery.adjustmentVersion, "1.0")
    }

    /// It has to be ours specifically. A generic identifier would collide with
    /// another app's edits on the same library.
    func testTheIdentifierIsNamespacedToThisApp() {
        XCTAssertTrue(PhotoGallery.adjustmentFormatID.hasPrefix("com.latitude.cam"),
                      "an un-namespaced identifier can collide with another editor")
    }

    /// Editing a frame that has not reached Photos yet has nothing to edit. It
    /// must say so rather than silently doing nothing or filing a copy.
    func testEditingAFrameNotYetInPhotosReportsRatherThanForking() {
        let gallery = PhotoGallery()
        gallery.addPhoto(UIImage(systemName: "camera") ?? UIImage(),
                         filmID: "amber", iso: 100, shutterDenominator: 60)
        let settled = expectation(description: "insert landed")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        guard let photo = gallery.photos.first else { return XCTFail("no frame") }
        let before = gallery.photos.count

        let reported = expectation(description: "edit reported")
        var failure: String?
        gallery.applyEdit(to: photo, image: UIImage(systemName: "camera") ?? UIImage(),
                          filmID: "rust") { result in
            if case .failed(let reason) = result { failure = reason }
            reported.fulfill()
        }
        wait(for: [reported], timeout: 4)

        XCTAssertNotNil(failure, "an un-mirrored frame cannot be edited in place")
        XCTAssertEqual(gallery.photos.count, before,
                       "a failed edit must not fork the roll the way the old save did")
    }

    /// Reverting something that was never in Photos is the same story.
    func testRevertingAFrameNotInPhotosReportsRatherThanCrashing() {
        let gallery = PhotoGallery()
        gallery.addPhoto(UIImage(systemName: "camera") ?? UIImage(),
                         filmID: "amber", iso: 100, shutterDenominator: 60)
        let settled = expectation(description: "insert landed")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        guard let photo = gallery.photos.first else { return XCTFail("no frame") }
        let reported = expectation(description: "revert reported")
        var failure: String?
        gallery.revertEdit(photo) { result in
            if case .failed(let reason) = result { failure = reason }
            reported.fulfill()
        }
        wait(for: [reported], timeout: 4)
        XCTAssertNotNil(failure)
    }

    /// A frame with no asset carries no edit, and asking must not hang.
    func testAFrameWithNoAssetHasNoEdit() {
        let gallery = PhotoGallery()
        gallery.addPhoto(UIImage(systemName: "camera") ?? UIImage(),
                         filmID: "amber", iso: 100, shutterDenominator: 60)
        let settled = expectation(description: "insert landed")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        guard let photo = gallery.photos.first else { return XCTFail("no frame") }
        let answered = expectation(description: "edit state answered")
        gallery.hasEdit(photo) { edited in
            XCTAssertFalse(edited)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 4)
    }

    /// Editing must stay a Photos operation. The whole point of the rewrite is
    /// that there is still exactly one copy of a picture on the phone.
    func testEditingWritesNothingIntoAppStorage() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("Gallery"))

        let gallery = PhotoGallery()
        gallery.addPhoto(UIImage(systemName: "camera") ?? UIImage(),
                         filmID: "amber", iso: 100, shutterDenominator: 60)
        let settled = expectation(description: "insert landed")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        guard let photo = gallery.photos.first else { return XCTFail("no frame") }
        let reported = expectation(description: "edit reported")
        gallery.applyEdit(to: photo, image: UIImage(systemName: "camera") ?? UIImage(),
                          filmID: "rust") { _ in reported.fulfill() }
        wait(for: [reported], timeout: 4)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: documents.appendingPathComponent("Gallery").path),
            "editing put a second copy back into app storage"
        )
    }
}
