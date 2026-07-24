import Foundation

enum PersistentLocationState: Equatable {
    case stopped
    case monitoring
    case sampling
    case systemPaused
}

enum PersistentMotionSignal: Equatable {
    case stationary
    case moving
    case unknown
}

enum PersistentLocationEvent: Equatable {
    case enabled(timestampMs: Int64)
    case motion(PersistentMotionSignal, timestampMs: Int64)
    case liveLocation(timestampMs: Int64)
    case systemStationary(timestampMs: Int64)
    case significantLocation(timestampMs: Int64)
    case visitArrival(timestampMs: Int64)
    case disabled(timestampMs: Int64)
}

enum PersistentLocationCommand: Equatable {
    case startSystemManagedLocation(profile: RecordingProfile)
    case stopSystemManagedLocation
    case startLowPowerMonitoring(profile: RecordingProfile)
    case stopLowPowerMonitoring
    case flushPendingTrackPoints
    case finishCurrentSegment(reason: String)
}

enum PersistentLocationStrategy: Equatable {
    case lowPowerMonitoring
    case systemManagedUpdates
}

extension RecordingProfile {
    var persistentLocationStrategy: PersistentLocationStrategy {
        switch self {
        case .eco:
            .lowPowerMonitoring
        case .daily, .high:
            .systemManagedUpdates
        }
    }
}

struct PersistentLocationCoordinator {
    private(set) var state: PersistentLocationState = .stopped

    private var profile: RecordingProfile

    init(profile: RecordingProfile) {
        self.profile = profile
    }

    mutating func updateProfile(_ profile: RecordingProfile) {
        self.profile = profile
    }

    mutating func handle(_ event: PersistentLocationEvent) -> [PersistentLocationCommand] {
        switch event {
        case .enabled:
            return handleEnabled()
        case .motion(let signal, let timestampMs):
            return handleMotion(signal, timestampMs: timestampMs)
        case .liveLocation:
            return handleLiveLocation()
        case .systemStationary:
            return handleSystemStationary()
        case .significantLocation:
            return []
        case .visitArrival:
            return []
        case .disabled:
            return handleDisabled()
        }
    }

    private mutating func handleEnabled() -> [PersistentLocationCommand] {
        switch profile.persistentLocationStrategy {
        case .lowPowerMonitoring:
            guard state == .stopped else { return [] }
            state = .monitoring
            return [.startLowPowerMonitoring(profile: profile)]
        case .systemManagedUpdates:
            guard state == .stopped else { return [] }
            state = .sampling
            return [.startSystemManagedLocation(profile: profile)]
        }
    }

    private mutating func handleDisabled() -> [PersistentLocationCommand] {
        switch state {
        case .stopped:
            return []
        case .monitoring:
            state = .stopped
            return [.stopLowPowerMonitoring]
        case .sampling, .systemPaused:
            state = .stopped
            return [.flushPendingTrackPoints, .stopSystemManagedLocation]
        }
    }

    private mutating func handleLiveLocation() -> [PersistentLocationCommand] {
        if state == .systemPaused {
            state = .sampling
        }
        return []
    }

    private mutating func handleSystemStationary() -> [PersistentLocationCommand] {
        guard state == .sampling else { return [] }
        state = .systemPaused
        return [.flushPendingTrackPoints, .finishCurrentSegment(reason: "system_paused")]
    }

    private mutating func handleMotion(_ signal: PersistentMotionSignal, timestampMs: Int64) -> [PersistentLocationCommand] {
        _ = signal
        _ = timestampMs
        return []
    }
}

enum LocationUpdateDestination: Equatable {
    case mapAnchor
    case persistentTrack
    case manualTrack
}

enum LocationUpdateRouter {
    static func destination(
        pendingMapAnchor: Bool,
        persistentRecordingEnabled: Bool,
        activeSessionKind: RecordingSessionKind?
    ) -> LocationUpdateDestination {
        if pendingMapAnchor {
            return .mapAnchor
        }
        if persistentRecordingEnabled, activeSessionKind != .manual {
            return .persistentTrack
        }
        return .manualTrack
    }
}

struct PersistentRecordingMetrics: Equatable {
    private(set) var standardLocationActiveSeconds = 0
    private(set) var systemPausedSeconds = 0
    private(set) var locationCallbacks = 0
    private(set) var acceptedTrackPoints = 0
    private(set) var databaseWriteBatches = 0
    private(set) var motionEvents = 0

    private var activeStartedAtMs: Int64?
    private var pausedStartedAtMs: Int64?

    mutating func markStandardLocationStarted(atMs timestampMs: Int64) {
        if let pausedStartedAtMs {
            systemPausedSeconds += Self.secondsBetween(pausedStartedAtMs, timestampMs)
            self.pausedStartedAtMs = nil
        }
        if activeStartedAtMs == nil {
            activeStartedAtMs = timestampMs
        }
    }

    mutating func markSystemPaused(atMs timestampMs: Int64) {
        if let activeStartedAtMs {
            standardLocationActiveSeconds += Self.secondsBetween(activeStartedAtMs, timestampMs)
            self.activeStartedAtMs = nil
        }
        if pausedStartedAtMs == nil {
            pausedStartedAtMs = timestampMs
        }
    }

    mutating func markStandardLocationStopped(atMs timestampMs: Int64) {
        if let activeStartedAtMs {
            standardLocationActiveSeconds += Self.secondsBetween(activeStartedAtMs, timestampMs)
            self.activeStartedAtMs = nil
        }
        if let pausedStartedAtMs {
            systemPausedSeconds += Self.secondsBetween(pausedStartedAtMs, timestampMs)
            self.pausedStartedAtMs = nil
        }
    }

    mutating func markLocationCallback() {
        locationCallbacks += 1
    }

    mutating func markAcceptedTrackPoint() {
        acceptedTrackPoints += 1
    }

    mutating func markDatabaseWriteBatch() {
        databaseWriteBatches += 1
    }

    mutating func markMotionEvent() {
        motionEvents += 1
    }

    var diagnosticSummary: String {
        "standardLocationActiveSeconds=\(standardLocationActiveSeconds) systemPausedSeconds=\(systemPausedSeconds) locationCallbacks=\(locationCallbacks) acceptedTrackPoints=\(acceptedTrackPoints) databaseWriteBatches=\(databaseWriteBatches) motionEvents=\(motionEvents)"
    }

    private static func secondsBetween(_ startMs: Int64, _ endMs: Int64) -> Int {
        max(0, Int((endMs - startMs) / 1_000))
    }
}
