import Foundation

enum AmbientSessionPolicy: Equatable {
    case daily
    case trip
}

enum SessionSegmentEvent: Equatable {
    case location(timestampMs: Int64)
    case visitArrival(timestampMs: Int64)
    case disabled(timestampMs: Int64)
}

enum SessionSegmentAction: Equatable {
    case none
    case reuseCurrent
    case startNew(origin: AmbientSessionOrigin, key: String)
    case finishCurrent
    case finishAndStartNew(origin: AmbientSessionOrigin, key: String)
}

struct SessionSegmenter {
    private let profile: RecordingProfile
    private var currentKey: String?
    private var tripIndex = 0

    init(profile: RecordingProfile) {
        self.profile = profile
    }

    mutating func action(for event: SessionSegmentEvent) -> SessionSegmentAction {
        switch event {
        case .location(let timestampMs):
            return actionForLocation(timestampMs)
        case .visitArrival:
            // Visit 不再按到达事件切段；Daily 段边界由 Core Location system pause 决定。
            return .none
        case .disabled:
            guard currentKey != nil else { return .none }
            currentKey = nil
            return .finishCurrent
        }
    }

    mutating func reset() {
        currentKey = nil
        tripIndex = 0
    }

    /// Core Location system pause 结束当前段；下一次 live location 会开新段。
    mutating func endCurrentSegment() {
        currentKey = nil
    }

    private mutating func actionForLocation(_ timestampMs: Int64) -> SessionSegmentAction {
        switch profile.ambientSessionPolicy {
        case .daily:
            let dayKey = AppFormatters.localDayKey(for: timestampMs)
            guard let currentKey else {
                self.currentKey = dayKey
                return .startNew(origin: .day, key: dayKey)
            }
            if currentKey == dayKey {
                return .reuseCurrent
            }
            self.currentKey = dayKey
            return .finishAndStartNew(origin: .day, key: dayKey)

        case .trip:
            guard currentKey == nil else { return .reuseCurrent }
            tripIndex += 1
            let key = "trip-\(tripIndex)"
            currentKey = key
            return .startNew(origin: .trip, key: key)
        }
    }
}
