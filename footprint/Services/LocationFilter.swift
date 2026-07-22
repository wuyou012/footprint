import CoreLocation
import Foundation

enum TrackPointRejectReason: String {
    case invalid
    case accuracy
    case tooClose
    case tooSoon
    case jump
}

enum TrackPointDecision {
    case accept(distanceMeters: Double?, elapsedSeconds: TimeInterval?)
    case reject(reason: TrackPointRejectReason, distanceMeters: Double?, elapsedSeconds: TimeInterval?)
}

nonisolated enum LocationFilter {
    private static let earthRadiusMeters = 6_371_008.8

    static func distanceMeters(from a: TrackPoint, to b: TrackPoint) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLat = (b.latitude - a.latitude) * .pi / 180
        let deltaLng = (b.longitude - a.longitude) * .pi / 180

        let sinLat = sin(deltaLat / 2)
        let sinLng = sin(deltaLng / 2)
        let h = sinLat * sinLat + cos(lat1) * cos(lat2) * sinLng * sinLng
        let clamped = min(1, max(0, h))
        return 2 * earthRadiusMeters * atan2(sqrt(clamped), sqrt(1 - clamped))
    }

    static func shouldAccept(previous: TrackPoint?, candidate: TrackPoint, profile: RecordingProfile) -> TrackPointDecision {
        guard candidate.longitude.isFinite,
              candidate.latitude.isFinite,
              abs(candidate.longitude) <= 180,
              abs(candidate.latitude) <= 90,
              candidate.timestampMs > 0
        else {
            return .reject(reason: .invalid, distanceMeters: nil, elapsedSeconds: nil)
        }

        if let accuracy = candidate.accuracy,
           (!accuracy.isFinite || accuracy > profile.maxAcceptedAccuracyMeters) {
            return .reject(reason: .accuracy, distanceMeters: nil, elapsedSeconds: nil)
        }

        guard let previous else {
            return .accept(distanceMeters: nil, elapsedSeconds: nil)
        }

        let elapsedSeconds = TimeInterval(candidate.timestampMs - previous.timestampMs) / 1000
        guard elapsedSeconds >= 0, elapsedSeconds.isFinite else {
            return .reject(reason: .invalid, distanceMeters: nil, elapsedSeconds: nil)
        }

        let distance = distanceMeters(from: previous, to: candidate)
        guard distance.isFinite else {
            return .reject(reason: .invalid, distanceMeters: nil, elapsedSeconds: elapsedSeconds)
        }

        if elapsedSeconds < profile.minIntervalSeconds {
            return .reject(reason: .tooSoon, distanceMeters: distance, elapsedSeconds: elapsedSeconds)
        }

        if distance < profile.minDistanceMeters {
            return .reject(reason: .tooClose, distanceMeters: distance, elapsedSeconds: elapsedSeconds)
        }

        if elapsedSeconds > 0, distance / elapsedSeconds > profile.maxSpeedMetersPerSecond {
            return .reject(reason: .jump, distanceMeters: distance, elapsedSeconds: elapsedSeconds)
        }

        return .accept(distanceMeters: distance, elapsedSeconds: elapsedSeconds)
    }
}
