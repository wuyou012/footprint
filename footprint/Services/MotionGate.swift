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
        switch snapshot.kind {
        case .walking, .running, .automotive, .cycling:
            // CMMotion 现在只作为交通方式标签和诊断；低置信 movement 仍保留标签价值。
            return .moving
        case .stationary:
            // 低置信 stationary 不能作为可靠停走信号；Daily 停走交给 Core Location system pause。
            return snapshot.confidence == .low ? .unknown : .stationary
        case .unknown:
            return .unknown
        }
    }
}
