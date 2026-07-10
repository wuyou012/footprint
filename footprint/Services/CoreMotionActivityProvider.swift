import Foundation

#if canImport(CoreMotion)
import CoreMotion

@MainActor
final class CoreMotionActivityProvider {
    var onDecision: ((MotionDecision, Int64) -> Void)?

    private let manager = CMMotionActivityManager()
    private(set) var active = false

    func start() {
        guard CMMotionActivityManager.isActivityAvailable(), !active else { return }
        active = true
        manager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            Task { @MainActor [weak self] in
                self?.emit(activity)
            }
        }
    }

    func stop() {
        guard active else { return }
        manager.stopActivityUpdates()
        active = false
    }

    private func emit(_ activity: CMMotionActivity) {
        let snapshot = MotionActivitySnapshot(
            kind: Self.kind(from: activity),
            confidence: Self.confidence(from: activity.confidence),
            timestampMs: Int64(activity.startDate.timeIntervalSince1970 * 1000)
        )
        onDecision?(MotionGate.decision(for: snapshot), snapshot.timestampMs)
    }

    private static func kind(from activity: CMMotionActivity) -> MotionActivityKind {
        if activity.stationary { return .stationary }
        if activity.automotive { return .automotive }
        if activity.cycling { return .cycling }
        if activity.running { return .running }
        if activity.walking { return .walking }
        return .unknown
    }

    private static func confidence(from confidence: CMMotionActivityConfidence) -> MotionConfidence {
        switch confidence {
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        @unknown default:
            return .low
        }
    }
}
#endif
