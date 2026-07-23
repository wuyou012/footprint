import Foundation

nonisolated enum AwardOverlayReloadPolicy {
    static let recordingPointInterval = 10

    static func shouldReloadAfterAcceptedPointChange(
        isRecording: Bool,
        lastReloadAcceptedCount: Int,
        currentAcceptedCount: Int
    ) -> Bool {
        guard isRecording else { return true }
        if currentAcceptedCount < lastReloadAcceptedCount {
            return true
        }
        return currentAcceptedCount - lastReloadAcceptedCount >= recordingPointInterval
    }
}
