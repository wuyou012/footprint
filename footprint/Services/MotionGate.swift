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
            // 运动类一律视为移动——即使低置信也宁可记录。实测步行时（手机在兜里/包里/
            // 慢走）CMMotion 常报低置信；旧逻辑一刀切判 unknown 会漏记整段步行。
            return .moving
        case .stationary:
            // 只有足够置信的静止才进 dormant 停止密集记录；低置信静止不轻易停。
            return snapshot.confidence == .low ? .unknown : .stationary
        case .unknown:
            return .unknown
        }
    }
}
