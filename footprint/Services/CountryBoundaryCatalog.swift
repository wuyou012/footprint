import Foundation

nonisolated struct CountryBoundaryCatalog: Sendable {
    enum CatalogError: Error {
        case missingResource
    }

    private static let sharedCache = Cache()
    private let loader: @Sendable () throws -> Data
    private let cache: Cache

    nonisolated init(resourceName: String = "country_boundaries", resourceExtension: String = "geojson") {
        self.loader = {
            guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) else {
                throw CatalogError.missingResource
            }
            return try Data(contentsOf: url)
        }
        self.cache = Self.sharedCache
    }

    nonisolated init(loader: @escaping @Sendable () throws -> Data) {
        self.loader = loader
        self.cache = Cache()
    }

    nonisolated func loadCountries() throws -> [CountryBoundary] {
        try cache.loadCountries(loader: loader) { data in
            try Self.decodeCountries(from: data)
        }
    }

    nonisolated private static func decodeCountries(from data: Data) throws -> [CountryBoundary] {
        let collection = try JSONDecoder().decode(CountryBoundaryFeatureCollection.self, from: data)
        return collection.features.compactMap { feature in
            let countryId = normalizeCountryId(feature.properties.countryId ?? feature.properties.id)
            let polygons = feature.geometry.boundaryPolygons(featureID: countryId)
            guard !countryId.isEmpty, !polygons.isEmpty else { return nil }

            let bounds = Self.bounds(for: polygons)
            return CountryBoundary(
                countryId: countryId,
                countryCode: normalizeDisplayCode(feature.properties.countryCode ?? countryId),
                countryName: feature.properties.countryName
                    ?? feature.properties.nameEn
                    ?? feature.properties.nameZh
                    ?? countryId,
                minLatitude: bounds.minLatitude,
                maxLatitude: bounds.maxLatitude,
                minLongitude: bounds.minLongitude,
                maxLongitude: bounds.maxLongitude,
                boundaryPolygons: polygons,
                sourceComponentCountryIds: feature.properties.sourceComponentCountryIds,
                sourceComponentRegionIds: feature.properties.sourceComponentRegionIds
            )
        }
        .sorted { lhs, rhs in
            if lhs.countryId != rhs.countryId {
                return lhs.countryId < rhs.countryId
            }
            return lhs.countryName < rhs.countryName
        }
    }

    nonisolated private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var countries: [CountryBoundary]?

        func loadCountries(
            loader: @Sendable () throws -> Data,
            decoder: (Data) throws -> [CountryBoundary]
        ) throws -> [CountryBoundary] {
            lock.lock()
            defer { lock.unlock() }
            if let countries {
                return countries
            }

            let decodedCountries = try decoder(loader())
            countries = decodedCountries
            return decodedCountries
        }
    }

    nonisolated private static func bounds(
        for polygons: [RegionAchievementBoundaryPolygon]
    ) -> (minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        let coordinates = polygons.flatMap(\.coordinates)
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        return (
            minLatitude: latitudes.min() ?? 0,
            maxLatitude: latitudes.max() ?? 0,
            minLongitude: longitudes.min() ?? 0,
            maxLongitude: longitudes.max() ?? 0
        )
    }

    nonisolated private static func normalizeCountryId(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .uppercased()
    }

    nonisolated private static func normalizeDisplayCode(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

nonisolated private struct CountryBoundaryFeatureCollection: Decodable {
    let features: [CountryBoundaryFeature]
}

nonisolated private struct CountryBoundaryFeature: Decodable {
    let properties: CountryBoundaryProperties
    let geometry: CountryBoundaryGeometry
}

nonisolated private struct CountryBoundaryProperties: Decodable {
    let id: String
    let countryId: String?
    let countryCode: String?
    let countryName: String?
    let nameZh: String?
    let nameEn: String?
    let sourceComponentCountryIds: [String]
    let sourceComponentRegionIds: [String]

    enum CodingKeys: CodingKey {
        case id
        case countryId
        case country_id
        case countryCode
        case countryName
        case nameZh
        case nameEn
        case sourceComponentCountryIds
        case sourceComponentRegionIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        countryId = try container.decodeIfPresent(String.self, forKey: .countryId)
            ?? container.decodeIfPresent(String.self, forKey: .country_id)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        countryName = try container.decodeIfPresent(String.self, forKey: .countryName)
        nameZh = try container.decodeIfPresent(String.self, forKey: .nameZh)
        nameEn = try container.decodeIfPresent(String.self, forKey: .nameEn)
        sourceComponentCountryIds = try container.decodeIfPresent([String].self, forKey: .sourceComponentCountryIds) ?? []
        sourceComponentRegionIds = try container.decodeIfPresent([String].self, forKey: .sourceComponentRegionIds) ?? []
    }
}

nonisolated private struct CountryBoundaryGeometry: Decodable {
    let type: String
    let polygons: [[[[Double]]]]

    enum CodingKeys: CodingKey {
        case type
        case coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)

        switch type {
        case "Polygon":
            let coordinates = try container.decode([[[Double]]].self, forKey: .coordinates)
            polygons = [coordinates]
        case "MultiPolygon":
            polygons = try container.decode([[[[Double]]]].self, forKey: .coordinates)
        default:
            polygons = []
        }
    }

    nonisolated func boundaryPolygons(featureID: String) -> [RegionAchievementBoundaryPolygon] {
        polygons.enumerated().compactMap { index, polygon in
            guard let outerRing = polygon.first else { return nil }
            let coordinates = outerRing.compactMap { pair -> RegionAchievementBoundaryCoordinate? in
                guard pair.count >= 2 else { return nil }
                return RegionAchievementBoundaryCoordinate(
                    latitude: pair[1],
                    longitude: pair[0]
                )
            }
            guard coordinates.count >= 3 else { return nil }
            return RegionAchievementBoundaryPolygon(
                id: "\(featureID)-\(index)",
                coordinates: coordinates
            )
        }
    }
}
