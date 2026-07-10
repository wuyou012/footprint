import Foundation

enum MotionActivityKind: Equatable {
    case stationary
    case walking
    case running
    case automotive
    case cycling
    case unknown
}

enum MotionConfidence: Equatable {
    case low
    case medium
    case high
}

struct MotionActivitySnapshot: Equatable {
    var kind: MotionActivityKind
    var confidence: MotionConfidence
    var timestampMs: Int64
}

enum MotionDecision: Equatable {
    case stationary
    case moving
    case unknown
}

enum MotionGate {
    static func decision(for snapshot: MotionActivitySnapshot) -> MotionDecision {
        guard snapshot.confidence != .low else { return .unknown }

        switch snapshot.kind {
        case .stationary:
            return .stationary
        case .walking, .running, .automotive, .cycling:
            return .moving
        case .unknown:
            return .unknown
        }
    }
}
