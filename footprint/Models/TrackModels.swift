import CoreLocation
import Foundation

enum RecordingProfile: String, CaseIterable, Identifiable {
    case high
    case daily
    case eco

    var id: String { rawValue }

    var label: String {
        switch self {
        case .high: "High"
        case .daily: "Daily"
        case .eco: "Eco"
        }
    }

    var description: String {
        switch self {
        case .high:
            "Finer track, higher battery. Best for short walks."
        case .daily:
            "Balanced for city walks & commutes. Recommended."
        case .eco:
            "Saves battery, coarser track. May skip small turns."
        }
    }

    var desiredAccuracy: CLLocationAccuracy {
        switch self {
        case .high: kCLLocationAccuracyNearestTenMeters
        case .daily, .eco: kCLLocationAccuracyHundredMeters
        }
    }

    var distanceFilter: CLLocationDistance {
        switch self {
        case .high: 10
        case .daily: 30
        case .eco: 200
        }
    }

    var maxAcceptedAccuracyMeters: CLLocationAccuracy {
        switch self {
        case .high: 100
        case .daily: 250
        case .eco: 500
        }
    }

    var minDistanceMeters: CLLocationDistance {
        switch self {
        case .high: 8
        case .daily: 25
        case .eco: 180
        }
    }

    var minIntervalSeconds: TimeInterval {
        switch self {
        case .high: 1
        case .daily: 10
        case .eco: 30
        }
    }

    var statsRefreshInterval: TimeInterval {
        switch self {
        case .high: 1
        case .daily: 5
        case .eco: 15
        }
    }

    var maxSpeedMetersPerSecond: CLLocationSpeed { 70 }

    var stationaryTimeoutSeconds: Int {
        switch self {
        case .high: 300
        case .daily: 180
        case .eco: 0
        }
    }

    var ambientSessionPolicy: AmbientSessionPolicy {
        switch self {
        case .high, .daily: .trip
        case .eco: .daily
        }
    }

    var usesDutyCycledAmbientLocation: Bool {
        self == .eco
    }
}

enum RecordingSessionKind: String, CaseIterable, Hashable {
    case manual
    case ambient
}

enum AmbientSessionOrigin: String, CaseIterable, Hashable {
    case day
    case visit
}

struct TrackPoint: Identifiable, Hashable {
    var id: Int64?
    var longitude: Double
    var latitude: Double
    var timestampMs: Int64
    var accuracy: Double?
    var speed: Double?
    var altitude: Double?
    var heading: Double?
    var sessionID: Int64?
    var segmentID: Int64?
    var source: String?
    var profile: RecordingProfile?
    var localDayKey: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
    }
}

struct RecordingStats: Equatable {
    var startedAtMs: Int64?
    var durationSeconds: TimeInterval
    var distanceMeters: Double
    var acceptedCount: Int
    var receivedCount: Int
    var lastFixMs: Int64?
    var lastAccuracy: Double?

    static let idle = RecordingStats(
        startedAtMs: nil,
        durationSeconds: 0,
        distanceMeters: 0,
        acceptedCount: 0,
        receivedCount: 0,
        lastFixMs: nil,
        lastAccuracy: nil
    )
}

struct DaySummary: Identifiable, Hashable {
    var dayKey: String
    var sessionCount: Int
    var pointCount: Int
    var distanceMeters: Double
    var durationSeconds: TimeInterval
    var firstStartedAtMs: Int64?
    var lastEndedAtMs: Int64?

    var id: String { dayKey }
}

struct DaySession: Identifiable, Hashable {
    var id: Int64
    var profile: RecordingProfile?
    var startMs: Int64?
    var endMs: Int64?
    var pointCount: Int
    var distanceMeters: Double
    var kind: RecordingSessionKind = .manual
    var origin: AmbientSessionOrigin?
}

struct ActiveRecordingSession {
    var sessionID: Int64
    var segmentID: Int64
    var profile: RecordingProfile
    var kind: RecordingSessionKind = .manual
    var origin: AmbientSessionOrigin?
    var startedAtMs: Int64
    var receivedCount: Int
    var acceptedCount: Int
    var rejectedCount: Int
    var distanceMeters: Double
    var lastAccepted: TrackPoint?
}
