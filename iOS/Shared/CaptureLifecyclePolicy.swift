import Foundation

/// ReplayKit's pause is a reversible lifecycle event. It does not authorize a
/// terminal error or a new stitching origin. Only a verified frame may complete
/// the resume transition when a pre-pause reference exists.
public struct CaptureLifecyclePolicy: Sendable {
    public enum State: String, Sendable { case active, paused, awaitingOverlap, finished }
    public private(set) var state: State = .active
    public private(set) var pauseCount = 0
    public private(set) var resumeCount = 0
    public private(set) var recoveredResumeCount = 0
    public private(set) var hasUnresolvedRejection = false
    private let startedAt: Double
    private var pauseBeganAt: Double?
    private var accumulatedPauseSeconds = 0.0
    private var requiresOverlap = false
    private var finishedAt: Double?

    public init(startedAt: Double = 0) { self.startedAt = startedAt }
    public var isFinished: Bool { state == .finished }
    public var canProcessFrames: Bool { state == .active || state == .awaitingOverlap }
    public var canStopForIdle: Bool { state == .active }
    public var needsOverlapAfterResume: Bool { state == .awaitingOverlap }
    public var hasUnverifiedContent: Bool { hasUnresolvedRejection || state == .awaitingOverlap }

    public mutating func rejectedFrame() {
        guard canProcessFrames else { return }
        hasUnresolvedRejection = true
    }

    @discardableResult
    public mutating func pause(at now: Double, requiresOverlap: Bool) -> Bool {
        guard state != .finished, state != .paused else { return false }
        self.requiresOverlap = requiresOverlap || state == .awaitingOverlap
        pauseBeganAt = now; state = .paused; pauseCount += 1
        return true
    }

    @discardableResult
    public mutating func resume(at now: Double) -> Bool {
        guard state == .paused else { return false }
        accumulatedPauseSeconds += max(0, now - (pauseBeganAt ?? now))
        pauseBeganAt = nil; resumeCount += 1
        state = requiresOverlap ? .awaitingOverlap : .active
        return true
    }

    /// Call for an exact unchanged frame or a core-verified displacement, never
    /// merely because a video callback arrived or an unrelated scene was seen.
    @discardableResult
    public mutating func verifiedFrame(at now: Double) -> Bool {
        guard canProcessFrames else { return false }
        hasUnresolvedRejection = false
        guard state == .awaitingOverlap else { return false }
        state = .active; requiresOverlap = false; recoveredResumeCount += 1
        return true
    }

    /// True only for the first terminal transition, including Pause→Finished.
    @discardableResult
    public mutating func finish(at now: Double) -> Bool {
        guard state != .finished else { return false }
        if let pauseBeganAt { accumulatedPauseSeconds += max(0, now - pauseBeganAt) }
        pauseBeganAt = nil; finishedAt = now; state = .finished
        return true
    }

    /// Used by duration and continuity timers. Paused wall time never consumes
    /// capture time or the grace period for finding a trustworthy overlap.
    public func activeElapsed(at now: Double) -> Double {
        let end = finishedAt ?? now
        let currentPause = pauseBeganAt.map { max(0, end - $0) } ?? 0
        return max(0, end - startedAt - accumulatedPauseSeconds - currentPause)
    }
}
