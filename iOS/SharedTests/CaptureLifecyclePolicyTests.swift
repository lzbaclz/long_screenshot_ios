import XCTest
@testable import ScrollCapture

final class CaptureLifecyclePolicyTests: XCTestCase {
    func testPauseKeepsSessionOpenAndFreezesActiveClock() {
        var policy = CaptureLifecyclePolicy(startedAt: 100)
        XCTAssertTrue(policy.pause(at: 110, requiresOverlap: true))
        XCTAssertFalse(policy.isFinished)
        XCTAssertFalse(policy.canProcessFrames)
        XCTAssertFalse(policy.canStopForIdle)
        XCTAssertEqual(policy.activeElapsed(at: 190), 10)
        XCTAssertFalse(policy.pause(at: 190, requiresOverlap: true))
        XCTAssertEqual(policy.pauseCount, 1)
    }

    func testResumeNeedsTrustedOverlapAndRestoresIdleOnlyAfterIt() {
        var policy = CaptureLifecyclePolicy(startedAt: 100)
        policy.pause(at: 110, requiresOverlap: true)
        XCTAssertTrue(policy.resume(at: 190))
        XCTAssertTrue(policy.canProcessFrames)
        XCTAssertTrue(policy.needsOverlapAfterResume)
        XCTAssertFalse(policy.canStopForIdle)
        XCTAssertEqual(policy.activeElapsed(at: 195), 15)
        // Receiving callbacks or waiting five seconds does not itself prove a bridge.
        XCTAssertEqual(policy.state, .awaitingOverlap)
        XCTAssertTrue(policy.verifiedFrame(at: 195))
        XCTAssertTrue(policy.canStopForIdle)
        XCTAssertFalse(policy.needsOverlapAfterResume)
        XCTAssertEqual(policy.recoveredResumeCount, 1)
        XCTAssertFalse(policy.verifiedFrame(at: 196))
    }

    func testPauseThenSystemFinishHasExactlyOneTerminalTransition() {
        var policy = CaptureLifecyclePolicy(startedAt: 0)
        policy.pause(at: 3, requiresOverlap: true)
        XCTAssertFalse(policy.hasUnverifiedContent)
        XCTAssertTrue(policy.finish(at: 30))
        XCTAssertEqual(policy.activeElapsed(at: 100), 3)
        XCTAssertFalse(policy.finish(at: 31))
        XCTAssertFalse(policy.resume(at: 31))
        XCTAssertFalse(policy.pause(at: 32, requiresOverlap: true))
        XCTAssertFalse(policy.verifiedFrame(at: 32))
        XCTAssertEqual(policy.pauseCount, 1)
        XCTAssertEqual(policy.resumeCount, 0)
    }

    func testPauseBeforeAnyReferenceDoesNotInventAResumeGap() {
        var policy = CaptureLifecyclePolicy()
        policy.pause(at: 2, requiresOverlap: false)
        policy.resume(at: 20)
        XCTAssertEqual(policy.state, .active)
        XCTAssertEqual(policy.activeElapsed(at: 23), 5)
    }

    func testPauseDuringResumeKeepsTheUnresolvedBridgeAndExcludesBothPauses() {
        var policy = CaptureLifecyclePolicy()
        policy.pause(at: 10, requiresOverlap: true)
        policy.resume(at: 20)
        policy.pause(at: 25, requiresOverlap: false)
        policy.resume(at: 100)
        XCTAssertTrue(policy.needsOverlapAfterResume)
        XCTAssertEqual(policy.activeElapsed(at: 102), 17)
        XCTAssertEqual(policy.pauseCount, 2)
        XCTAssertEqual(policy.resumeCount, 2)
    }

    func testContinuityGraceDoesNotExpireWhilePausedAndRejectedResumeCannotClearIt() {
        var lifecycle = CaptureLifecyclePolicy()
        var continuity = CaptureContinuityPolicy()
        lifecycle.pause(at: 3, requiresOverlap: true)
        lifecycle.resume(at: 100)
        for index in 0..<6 {
            XCTAssertFalse(continuity.reject(at: lifecycle.activeElapsed(at: 100 + Double(index)), hasStarted: true))
        }
        XCTAssertTrue(lifecycle.needsOverlapAfterResume)
        XCTAssertTrue(continuity.reject(at: lifecycle.activeElapsed(at: 108.1), hasStarted: true))
        XCTAssertTrue(lifecycle.needsOverlapAfterResume)
    }

    func testRejectedResumeRemainsPartialThroughAnotherPauseAndSystemFinish() {
        var policy = CaptureLifecyclePolicy()
        policy.pause(at: 1, requiresOverlap: true)
        policy.resume(at: 10)
        XCTAssertTrue(policy.hasUnverifiedContent)
        policy.rejectedFrame()
        policy.pause(at: 12, requiresOverlap: true)
        XCTAssertTrue(policy.hasUnverifiedContent)
        var manifest = CaptureSessionManifest()
        let id = UUID()
        manifest.pixelWidth = 144
        manifest.strips = [.init(id: id, fileName: "\(id.uuidString).png", pixelWidth: 144, pixelHeight: 900)]
        manifest.outputKind = .stitched
        manifest.diagnostics = .init(); manifest.diagnostics?.terminationCause = "systemStop"
        let partial = policy.hasUnverifiedContent
        XCTAssertTrue(policy.finish(at: 20))
        manifest.finalizeCapture(reason: "捕捉已由系统结束。", partial: partial)
        XCTAssertEqual(manifest.status, .partial)
        XCTAssertEqual(manifest.diagnostics?.terminationCause, "systemStop")
        XCTAssertEqual(manifest.pixelHeight, 900)
    }

    func testOnlyTrustedFramesClearTheUnresolvedRejectionFact() {
        var policy = CaptureLifecyclePolicy()
        policy.rejectedFrame()
        XCTAssertTrue(policy.hasUnverifiedContent)
        policy.pause(at: 1, requiresOverlap: true)
        policy.resume(at: 20)
        XCTAssertTrue(policy.hasUnverifiedContent)
        XCTAssertTrue(policy.verifiedFrame(at: 21))
        XCTAssertFalse(policy.hasUnverifiedContent)
        policy.rejectedFrame()
        XCTAssertFalse(policy.verifiedFrame(at: 22)) // already active, but a real verified frame clears the rejection
        XCTAssertFalse(policy.hasUnverifiedContent)
    }

    func testStorageFailureKeepsAnExplicitStopTrigger() {
        for cause in ["manual", "systemStop", "geometry"] {
            var diagnostics = CaptureDiagnostics()
            diagnostics.terminationCause = cause
            diagnostics.recordStorageFailure()
            XCTAssertEqual(diagnostics.terminationCause, cause)
            XCTAssertEqual(diagnostics.lastStage, "storage")
        }
        var unknown = CaptureDiagnostics()
        unknown.recordStorageFailure()
        XCTAssertEqual(unknown.terminationCause, "processingError")
    }

    func testOlderDiagnosticsDecodeWithoutLifecycleOrTimingFields() throws {
        var manifest = CaptureSessionManifest()
        manifest.diagnostics = CaptureDiagnostics()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as? [String: Any])
        var stats = try XCTUnwrap(json["diagnostics"] as? [String: Any])
        for key in ["stageTimings", "lifecycleState", "pauseCount", "resumeCount", "recoveredResumeCount",
                    "foregroundStatus", "foregroundCandidateCount", "foregroundSupportCount"] { stats.removeValue(forKey: key) }
        json["diagnostics"] = stats
        let decoded = try JSONDecoder().decode(CaptureSessionManifest.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertNil(decoded.diagnostics?.stageTimings)
        XCTAssertNil(decoded.diagnostics?.pauseCount)
    }

    func testNumericStageAggregatesRemainBoundedAndDoNotDoubleCountWhenPublished() {
        var pipeline = CaptureStageTimings()
        pipeline.record(.alignment, seconds: 0.005)
        pipeline.record(.alignment, seconds: 0.007)
        var adapter = CaptureStageTimings()
        adapter.record(.grayConversion, seconds: 0.003)
        let once = CaptureStageTimings.combined(pipeline: pipeline, adapter: adapter)
        let twice = CaptureStageTimings.combined(pipeline: once, adapter: adapter)
        XCTAssertEqual(once, twice)
        XCTAssertEqual(twice[.alignment]?.count, 2)
        XCTAssertEqual(twice[.alignment]?.maximumMilliseconds, 7)
        XCTAssertEqual(twice[.alignment]?.meanMilliseconds, 6)
        XCTAssertEqual(twice.values.count, 2)
    }
}
