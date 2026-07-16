import Foundation

enum PersistentLocationState: Equatable {
    case dormant
    case active
}

enum PersistentMotionSignal: Equatable {
    case stationary
    case moving
    case unknown
}

enum PersistentLocationEvent: Equatable {
    case motion(PersistentMotionSignal, timestampMs: Int64)
    case significantLocation(timestampMs: Int64)
    case visitArrival(timestampMs: Int64)
    case disabled(timestampMs: Int64)
}

enum PersistentLocationCommand: Equatable {
    case startContinuousLocation(profile: RecordingProfile)
    case startDutyCycledLocation(profile: RecordingProfile)
    case stopContinuousLocation
}

struct PersistentLocationCoordinator {
    private(set) var state: PersistentLocationState = .dormant

    private var profile: RecordingProfile
    private var stationarySinceMs: Int64?

    init(profile: RecordingProfile) {
        self.profile = profile
    }

    mutating func updateProfile(_ profile: RecordingProfile) {
        self.profile = profile
    }

    mutating func handle(_ event: PersistentLocationEvent) -> [PersistentLocationCommand] {
        switch event {
        case .motion(let signal, let timestampMs):
            return handleMotion(signal, timestampMs: timestampMs)
        case .significantLocation:
            return []
        case .visitArrival:
            // Visit 不再控制记录开关。实测步行时 iOS 频繁误报 visit 到达，旧逻辑会
            // dormant + 停 GPS → app 被挂起 → 整段步行丢失。记录 active/dormant 只由
            // 运动门控(CMMotion)决定；visit 仅用于 SessionSegmenter 的 trip 切段。
            return []
        case .disabled:
            guard state == .active else {
                stationarySinceMs = nil
                return []
            }
            state = .dormant
            stationarySinceMs = nil
            return [.stopContinuousLocation]
        }
    }

    private mutating func handleMotion(_ signal: PersistentMotionSignal, timestampMs: Int64) -> [PersistentLocationCommand] {
        switch signal {
        case .moving:
            stationarySinceMs = nil
            guard state == .dormant else { return [] }
            state = .active
            return profile.usesDutyCycledAmbientLocation
                ? [.startDutyCycledLocation(profile: profile)]
                : [.startContinuousLocation(profile: profile)]

        case .stationary:
            guard state == .active else { return [] }
            if profile.stationaryTimeoutSeconds == 0 {
                state = .dormant
                stationarySinceMs = nil
                return [.stopContinuousLocation]
            }

            let sinceMs = stationarySinceMs ?? timestampMs
            stationarySinceMs = sinceMs
            let elapsedSeconds = max(0, TimeInterval(timestampMs - sinceMs) / 1000)
            guard elapsedSeconds >= TimeInterval(profile.stationaryTimeoutSeconds) else { return [] }

            state = .dormant
            stationarySinceMs = nil
            return [.stopContinuousLocation]

        case .unknown:
            return []
        }
    }
}
