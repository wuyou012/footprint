import Foundation

#if DEBUG
nonisolated enum RegionAchievementDemoSeeds {
    nonisolated struct Point: Sendable {
        let regionId: String
        let coordinate: Coordinate
        let timestampMs: Int64
    }

    static let source = "debug-region-achievement-seed"

    static let points: [Point] = [
        Point(
            regionId: "US-CA-SF",
            coordinate: Coordinate(latitude: 37.7793, longitude: -122.4193),
            timestampMs: 1_783_590_000_000
        ),
        Point(
            regionId: "JP-13-SHINJUKU",
            coordinate: Coordinate(latitude: 35.6910, longitude: 139.7020),
            timestampMs: 1_783_590_060_000
        )
    ]
}
#endif
