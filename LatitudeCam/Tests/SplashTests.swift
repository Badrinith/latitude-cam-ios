//
//  SplashTests.swift
//  LatitudeCam
//
//  The splash is the one screen a user cannot navigate back to, so its exits
//  matter more than its looks: skip has to work, it has to hand off exactly
//  once, and it must never reappear after the first run.
//

import XCTest
import SwiftUI
@testable import LatitudeCam

@MainActor
final class SplashDirectorTests: XCTestCase {

    func testFourFeaturesAreHighlighted() {
        XCTAssertEqual(SplashDirector.features.count, 4)
    }

    func testEveryFeatureHasAGlyphAndCopy() {
        for feature in SplashDirector.features {
            XCTAssertFalse(feature.id.isEmpty)
            XCTAssertFalse(feature.title.isEmpty)
            XCTAssertFalse(feature.caption.isEmpty)
        }
    }

    func testFeatureIDsAreUnique() {
        let ids = Set(SplashDirector.features.map(\.id))
        XCTAssertEqual(ids.count, SplashDirector.features.count)
    }

    func testSequenceRunsForEightSeconds() {
        XCTAssertEqual(SplashDirector.beatDuration, 1.75, accuracy: 0.001)
        XCTAssertEqual(SplashDirector.totalDuration, 8.0, accuracy: 0.001)
    }

    /// Long enough to read a caption. Anything under a second and the copy is
    /// decoration rather than information.
    func testEachFeatureHoldsLongEnoughToRead() {
        XCTAssertGreaterThanOrEqual(SplashDirector.openDuration, 1.2)
    }

    func testStartsOnTheFirstFeature() {
        let director = SplashDirector()
        XCTAssertEqual(director.step, 0)
        XCTAssertEqual(director.currentFeature?.id, "exposure")
        XCTAssertFalse(director.isOutro)
        XCTAssertFalse(director.irisOpen)
    }

    func testSkipHandsOffImmediately() {
        let director = SplashDirector()
        var handoffs = 0
        director.start(reduceMotion: false) { handoffs += 1 }

        director.skip()

        XCTAssertTrue(director.isFinished)
        XCTAssertEqual(handoffs, 1)
    }

    /// A double tap during the transition must not push two screens.
    func testSkippingTwiceOnlyHandsOffOnce() {
        let director = SplashDirector()
        var handoffs = 0
        director.start(reduceMotion: false) { handoffs += 1 }

        director.skip()
        director.skip()
        director.skip()

        XCTAssertEqual(handoffs, 1)
    }

    func testSkipWorksWithoutStarting() {
        let director = SplashDirector()
        director.skip()
        XCTAssertTrue(director.isFinished)
    }

    func testStartingTwiceDoesNotRestartTheSequence() {
        let director = SplashDirector()
        var handoffs = 0
        director.start(reduceMotion: false) { handoffs += 1 }
        director.start(reduceMotion: false) { handoffs += 100 }

        director.skip()
        XCTAssertEqual(handoffs, 1, "the second start replaced the handoff")
    }

    func testReduceMotionStillHandsOff() {
        let director = SplashDirector()
        var handoffs = 0
        director.start(reduceMotion: true) { handoffs += 1 }

        XCTAssertTrue(director.irisOpen, "reduced motion should still show the content")
        director.skip()
        XCTAssertEqual(handoffs, 1)
    }

    func testOutroHasNoCurrentFeature() {
        let director = SplashDirector()
        XCTAssertNotNil(director.currentFeature)
        XCTAssertFalse(director.isOutro)
    }
}

// MARK: - Aperture

final class IrisApertureTests: XCTestCase {

    private let frame = CGRect(x: 0, y: 0, width: 100, height: 100)

    func testClosedApertureDrawsNothing() {
        XCTAssertTrue(IrisAperture(openness: 0).path(in: frame).isEmpty)
    }

    func testNegativeOpennessIsTreatedAsClosed() {
        XCTAssertTrue(IrisAperture(openness: -2).path(in: frame).isEmpty)
    }

    /// At full open the hexagon has to sit inside its frame — using the diagonal
    /// as its reach made it circumscribe the frame and read as a square.
    func testFullOpenFitsInsideTheFrame() {
        let bounds = IrisAperture(openness: 1).path(in: frame).boundingRect
        XCTAssertEqual(bounds.width, 86.6, accuracy: 1.0)
        XCTAssertEqual(bounds.height, 100, accuracy: 1.0)
        XCTAssertGreaterThanOrEqual(bounds.minX, -0.5)
    }

    func testApertureIsCentred() {
        let bounds = IrisAperture(openness: 1).path(in: frame).boundingRect
        XCTAssertEqual(bounds.midX, frame.midX, accuracy: 0.5)
        XCTAssertEqual(bounds.midY, frame.midY, accuracy: 0.5)
    }

    /// The hand-off works by opening past the frame, so anything above 1 has to
    /// actually spill outside it.
    func testFloodingClearsTheFrame() {
        let bounds = IrisAperture(openness: 3.2).path(in: frame).boundingRect
        XCTAssertGreaterThan(bounds.width, frame.width)
        XCTAssertLessThan(bounds.minY, 0)
    }

    func testOpeningIsMonotonic() {
        var previous = 0.0
        for step in 1...20 {
            let width = IrisAperture(openness: Double(step) / 10).path(in: frame).boundingRect.width
            XCTAssertGreaterThan(width, previous)
            previous = width
        }
    }

    func testAnimatableDataRoundTrips() {
        var iris = IrisAperture(openness: 0.4)
        XCTAssertEqual(iris.animatableData, 0.4, accuracy: 0.0001)
        iris.animatableData = 0.9
        XCTAssertEqual(iris.openness, 0.9, accuracy: 0.0001)
    }
}

// MARK: - Entry flow

@MainActor
final class ColdLaunchFlowTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Pref.onboarded)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Pref.onboarded)
        super.tearDown()
    }

    func testLaunchesOnTheSplash() {
        XCTAssertEqual(AppState().screen, .splash)
    }

    func testFirstRunGoesToOnboarding() {
        let app = AppState()
        app.finishSplash()
        XCTAssertEqual(app.screen, .onboarding)
    }

    /// Cold launch only in the sense that matters: the tour happens once, and
    /// every launch after it opens straight onto the camera.
    func testLaterRunsGoStraightToTheViewfinder() {
        let first = AppState()
        first.finishSplash()
        first.completeOnboarding()
        XCTAssertEqual(first.screen, .viewfinder)

        let second = AppState()
        second.finishSplash()
        XCTAssertEqual(second.screen, .viewfinder)
    }

    func testCompletingOnboardingPersists() {
        AppState().completeOnboarding()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Pref.onboarded))
    }

    /// Nothing in the app routes back to the splash, so it cannot replay while
    /// the process is alive.
    func testNoScreenReturnsToTheSplash() {
        let app = AppState()
        app.completeOnboarding()
        for screen in [Screen.viewfinder, .filmSim, .library, .edit, .review, .settings] {
            app.go(screen)
            XCTAssertNotEqual(app.screen, .splash)
        }
    }
}
