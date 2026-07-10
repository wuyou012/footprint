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
            guard profile.ambientSessionPolicy == .trip, currentKey != nil else { return .none }
            currentKey = nil
            return .finishCurrent
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
            return .startNew(origin: .visit, key: key)
        }
    }
}
