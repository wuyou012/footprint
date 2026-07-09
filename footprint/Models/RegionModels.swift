import Foundation

nonisolated enum Datum: String, Codable, Hashable, Sendable {
    case wgs84
    case gcj02
}

nonisolated struct Coordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

nonisolated struct BBox: Codable, Hashable, Sendable {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double

    init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = min(minLatitude, maxLatitude)
        self.maxLatitude = max(minLatitude, maxLatitude)
        self.minLongitude = min(minLongitude, maxLongitude)
        self.maxLongitude = max(minLongitude, maxLongitude)
    }

    init(coordinates: [Coordinate]) {
        self.init(
            minLatitude: coordinates.map(\.latitude).min() ?? 0,
            maxLatitude: coordinates.map(\.latitude).max() ?? 0,
            minLongitude: coordinates.map(\.longitude).min() ?? 0,
            maxLongitude: coordinates.map(\.longitude).max() ?? 0
        )
    }

    func contains(_ coordinate: Coordinate, padding: Double = 0) -> Bool {
        coordinate.latitude >= minLatitude - padding
            && coordinate.latitude <= maxLatitude + padding
            && coordinate.longitude >= minLongitude - padding
            && coordinate.longitude <= maxLongitude + padding
    }
}

nonisolated enum RegionLevel: String, Codable, Hashable, Sendable {
    case country
    case admin1
    case city
    case district

    var specificity: Int {
        switch self {
        case .country: 0
        case .admin1: 1
        case .city: 2
        case .district: 3
        }
    }
}

nonisolated struct Region: Identifiable, Codable, Hashable, Sendable {
    let regionId: String
    let level: RegionLevel
    let datum: Datum
    let bbox: BBox
    let parentId: String?
    let nameZh: String
    let nameEn: String
    let countryCode: String

    var id: String { regionId }
}

nonisolated struct RegionRing: Codable, Hashable, Sendable {
    let coordinates: [Coordinate]

    init(coordinates: [Coordinate]) {
        self.coordinates = coordinates
    }

    var closedCoordinates: [Coordinate] {
        guard let first = coordinates.first, coordinates.last != first else {
            return coordinates
        }
        return coordinates + [first]
    }
}

nonisolated struct RegionPolygon: Codable, Hashable, Sendable {
    let exterior: RegionRing
    let holes: [RegionRing]

    init(exterior: RegionRing, holes: [RegionRing] = []) {
        self.exterior = exterior
        self.holes = holes
    }

    var bbox: BBox {
        BBox(coordinates: exterior.coordinates)
    }
}

nonisolated protocol RegionDataProvider: Sendable {
    func regions() throws -> [Region]
    func geometry(for regionId: String) throws -> [RegionPolygon]
}
