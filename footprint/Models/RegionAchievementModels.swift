import CoreLocation
import Foundation

struct RegionAchievementCountry: Identifiable, Hashable, Sendable {
    let countryCode: String
    let countryName: String
    let cities: [RegionAchievementCity]

    var id: String { countryCode }

    var cityCount: Int { cities.count }

    var lastSeenMs: Int64? {
        cities.compactMap(\.lastSeenMs).max()
    }
}

struct RegionAchievementCity: Identifiable, Hashable, Sendable {
    let cityKey: String
    let countryCode: String
    let countryName: String
    let adminArea: String?
    let cityName: String
    let firstSeenMs: Int64?
    let lastSeenMs: Int64?
    let cellCount: Int

    var id: String { cityKey }

    var subtitle: String {
        guard let adminArea, !adminArea.isEmpty, adminArea != cityName else {
            return countryName
        }
        return "\(adminArea), \(countryName)"
    }
}

struct RegionAchievementCandidateCell: Sendable {
    let cellKey: String
    let latitude: Double
    let longitude: Double
    let firstPointID: Int64
    let firstSeenMs: Int64
    let lastSeenMs: Int64
    let pointCount: Int

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

struct RegionAchievementResolvedPlace: Sendable {
    let countryCode: String
    let countryName: String
    let adminArea: String?
    let cityName: String
    let cityKey: String
}

struct RegionAchievementSyncResult: Sendable {
    let scannedCells: Int
    let resolvedCells: Int
    let newCities: Int
    let hasMore: Bool
}

struct RegionAchievementMapCity: Identifiable, Hashable, Sendable {
    let cityKey: String
    let countryCode: String
    let countryName: String
    let adminArea: String?
    let cityName: String
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double
    let cellCount: Int
    let colorIndex: Int
    let isUnlocked: Bool
    let cityKeyAliases: [String]
    let boundaryPolygons: [RegionAchievementBoundaryPolygon]

    var id: String { cityKey }

    var subtitle: String {
        guard let adminArea, !adminArea.isEmpty, adminArea != cityName else {
            return countryName
        }
        return "\(adminArea), \(countryName)"
    }

    var centerCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
    }

    var boundaryCoordinates: [CLLocationCoordinate2D] {
        boundaryPolygons.first?.mapCoordinates ?? generatedBoundaryCoordinates
    }

    var closedBoundaryCoordinates: [CLLocationCoordinate2D] {
        guard let first = boundaryCoordinates.first else { return [] }
        return boundaryCoordinates + [first]
    }

    var mapBoundaryPolygons: [RegionAchievementBoundaryPolygon] {
        if !boundaryPolygons.isEmpty {
            return boundaryPolygons
        }
        return [
            RegionAchievementBoundaryPolygon(
                id: "\(cityKey)-generated-boundary",
                coordinates: generatedBoundaryCoordinates.map {
                    RegionAchievementBoundaryCoordinate(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                }
            )
        ]
    }

    nonisolated var matchKeys: [String] {
        Array(Set([cityKey] + cityKeyAliases))
    }

    nonisolated func applyingUnlock(from city: RegionAchievementMapCity) -> RegionAchievementMapCity {
        RegionAchievementMapCity(
            cityKey: cityKey,
            countryCode: countryCode,
            countryName: countryName,
            adminArea: adminArea,
            cityName: cityName,
            minLatitude: minLatitude,
            maxLatitude: maxLatitude,
            minLongitude: minLongitude,
            maxLongitude: maxLongitude,
            cellCount: max(cellCount, city.cellCount),
            colorIndex: colorIndex,
            isUnlocked: true,
            cityKeyAliases: cityKeyAliases,
            boundaryPolygons: boundaryPolygons
        )
    }

    private var generatedBoundaryCoordinates: [CLLocationCoordinate2D] {
        let center = centerCoordinate
        let latitudeRadius = max(0.055, (maxLatitude - minLatitude) / 2)
        let longitudeRadius = max(0.055, (maxLongitude - minLongitude) / 2)
        let phase = Double(abs(cityKey.hashValue % 360)) * .pi / 180
        let vertexCount = 24

        return (0..<vertexCount).map { index in
            let angle = Double(index) / Double(vertexCount) * 2 * .pi
            let wobble = 1
                + 0.16 * sin(angle * 3 + phase)
                + 0.09 * cos(angle * 5 + phase * 0.7)
            return CLLocationCoordinate2D(
                latitude: center.latitude + sin(angle) * latitudeRadius * wobble,
                longitude: center.longitude + cos(angle) * longitudeRadius * wobble
            )
        }
    }
}

struct RegionAchievementBoundaryPolygon: Identifiable, Hashable, Sendable {
    let id: String
    let coordinates: [RegionAchievementBoundaryCoordinate]

    var mapCoordinates: [CLLocationCoordinate2D] {
        coordinates.map(\.coordinate)
    }

    var closedMapCoordinates: [CLLocationCoordinate2D] {
        guard let first = mapCoordinates.first else { return [] }
        return mapCoordinates + [first]
    }
}

struct RegionAchievementBoundaryCoordinate: Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
