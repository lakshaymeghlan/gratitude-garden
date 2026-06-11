import XCTest
import SwiftUI
@testable import GratitudeGarden

/// Tests for the pure parts of the rendering layer — the snapshot→style mapping, the snapshot
/// helpers, and sprite integrity. (The drawing itself is visual; we verify it via previews.)
final class GardenRenderingTests: XCTestCase {

    // MARK: Snapshot helpers

    func testWiltFractionMapsLevelsToZeroToOne() {
        XCTAssertEqual(GardenSnapshot.preview(vitality: .thriving, wiltLevel: 0).wiltFraction, 0)
        let one = GardenSnapshot.preview(vitality: .drooping, wiltLevel: 1).wiltFraction
        let full = GardenSnapshot.preview(vitality: .dormant, wiltLevel: GardenRules.maxWiltLevel).wiltFraction
        XCTAssertGreaterThan(one, 0)
        XCTAssertLessThan(one, 1)
        XCTAssertEqual(full, 1)
    }

    func testRenderSeedIsDeterministicForParity() {
        let a = GardenSnapshot.preview(growth: .blooming, totalEntries: 12, consecutiveDayCount: 5)
        let b = GardenSnapshot.preview(growth: .blooming, totalEntries: 12, consecutiveDayCount: 5)
        XCTAssertEqual(a.renderSeed, b.renderSeed, "Same state → same seed → identical app/widget layout")
        let c = GardenSnapshot.preview(growth: .blooming, totalEntries: 13, consecutiveDayCount: 5)
        XCTAssertNotEqual(a.renderSeed, c.renderSeed, "Different state should generally reseed")
    }

    // MARK: Style mapping (the forgiving visual contract)

    func testThrivingIsFullColorAndUpright() {
        let style = GardenStyle.make(for: .preview(vitality: .thriving))
        XCTAssertEqual(style.saturation, 1.0, accuracy: 0.0001)
        XCTAssertEqual(style.droopDegrees, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(style.fireflyCount, 0)
    }

    func testDroopingDesaturatesAndTiltsProgressively() {
        let s1 = GardenStyle.make(for: .preview(vitality: .drooping, wiltLevel: 1))
        let s3 = GardenStyle.make(for: .preview(vitality: .drooping, wiltLevel: 3))
        XCTAssertLessThan(s1.saturation, 1.0, "Drooping is gently desaturated…")
        XCTAssertLessThan(s3.saturation, s1.saturation, "…and more so as it deepens")
        XCTAssertGreaterThan(s3.droopDegrees, s1.droopDegrees, "Tilt increases with wilt")
        XCTAssertLessThanOrEqual(s3.fireflyCount, s1.fireflyCount, "Particle activity reduces")
    }

    func testDormantIsMutedButNotBlack() {
        let style = GardenStyle.make(for: .preview(vitality: .dormant, wiltLevel: 4))
        XCTAssertGreaterThan(style.saturation, 0.3, "Dormant is muted, never colorless/dead")
        XCTAssertLessThan(style.saturation, 0.7)
        XCTAssertGreaterThanOrEqual(style.fireflyCount, 1, "A little warm life remains — peaceful, not dead")
    }

    func testRevivalLerpGoesFromMutedTowardThriving() {
        let target = GardenStyle.make(for: .preview(isReviving: true))
        let pre = GardenStyle.preRevival(target: target)
        let mid = GardenStyle.lerp(pre, target, 0.5)
        XCTAssertEqual(pre.ambientOpacity, 0, "Lights start off…")
        XCTAssertGreaterThan(mid.ambientOpacity, pre.ambientOpacity, "…and fade in")
        XCTAssertLessThan(mid.droopDegrees, pre.droopDegrees, "Flowers straighten during revival")
        XCTAssertGreaterThan(mid.saturation, pre.saturation, "Color returns during revival")
        XCTAssertEqual(GardenStyle.lerp(pre, target, 1.0), target, "Ends exactly at the thriving target")
    }

    // MARK: Sprite integrity

    func testEveryGrowthStageHasAtLeastOneFrameWithContent() {
        let art = ProceduralGardenArt()
        for stage in GrowthStage.allCases {
            let frames = art.plantFrames(for: stage)
            XCTAssertFalse(frames.isEmpty, "\(stage) has no frames")
            let nonEmpty = frames[0].rows.contains { $0.contains { $0 != "." } }
            XCTAssertTrue(nonEmpty, "\(stage) sprite is blank")
            XCTAssertEqual(frames[0].height, 20, "Sprites share the 20-tall grid")
        }
    }
}
