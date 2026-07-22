import Foundation

nonisolated struct CityBoundaryCatalog: Sendable {
    enum CatalogError: Error {
        case missingResource
    }

    private static let sharedCache = Cache()
    private let loader: @Sendable () throws -> Data
    private let cache: Cache

    nonisolated init(resourceName: String = "city_boundaries", resourceExtension: String = "geojson") {
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

    nonisolated func loadCities() throws -> [RegionAchievementMapCity] {
        try cache.loadCities(loader: loader) { data in
            try Self.decodeCities(from: data)
        }
    }

    nonisolated private static func decodeCities(from data: Data) throws -> [RegionAchievementMapCity] {
        let collection = try JSONDecoder().decode(FeatureCollection.self, from: data)
        return collection.features.enumerated().compactMap { index, feature in
            let polygons = feature.geometry.boundaryPolygons(featureID: feature.properties.id)
            guard !polygons.isEmpty else { return nil }

            let bounds = Self.bounds(for: polygons)
            let cityKey = Self.normalizedCityKey(
                feature.properties.cityKey
                    ?? Self.cityKey(
                        countryCode: feature.properties.countryCode,
                        adminArea: feature.properties.adminArea,
                        cityName: feature.properties.cityName
                    )
            )

            return RegionAchievementMapCity(
                cityKey: cityKey,
                regionId: feature.properties.canonicalRegionId,
                countryCode: Self.normalize(feature.properties.countryCode),
                countryName: feature.properties.countryName,
                adminArea: feature.properties.adminArea,
                cityName: feature.properties.cityName,
                minLatitude: bounds.minLatitude,
                maxLatitude: bounds.maxLatitude,
                minLongitude: bounds.minLongitude,
                maxLongitude: bounds.maxLongitude,
                cellCount: 0,
                colorIndex: index,
                isUnlocked: false,
                cityKeyAliases: feature.properties.aliases.map(Self.normalizedCityKey),
                boundaryPolygons: polygons
            )
        }
    }

    nonisolated private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var cities: [RegionAchievementMapCity]?

        func loadCities(
            loader: @Sendable () throws -> Data,
            decoder: (Data) throws -> [RegionAchievementMapCity]
        ) throws -> [RegionAchievementMapCity] {
            lock.lock()
            defer { lock.unlock() }
            if let cities {
                return cities
            }

            let decodedCities = try decoder(loader())
            cities = decodedCities
            return decodedCities
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

    nonisolated private static func cityKey(countryCode: String, adminArea: String?, cityName: String) -> String {
        [
            normalize(countryCode),
            normalize(adminArea),
            normalize(cityName)
        ].joined(separator: "|")
    }

    nonisolated private static func normalizedCityKey(_ value: String) -> String {
        value
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { normalize(String($0)) }
            .joined(separator: "|")
    }

    nonisolated private static func normalize(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "|", with: " ")
        ?? ""
    }
}

nonisolated private struct FeatureCollection: Decodable {
    let features: [CityBoundaryFeature]
}

nonisolated private struct CityBoundaryFeature: Decodable {
    let properties: CityBoundaryProperties
    let geometry: CityBoundaryGeometry
}

nonisolated private struct CityBoundaryProperties: Decodable {
    let id: String
    let regionId: String?
    let cityKey: String?
    let countryCode: String
    let countryName: String
    let adminArea: String?
    let cityName: String
    let aliases: [String]

    enum CodingKeys: CodingKey {
        case id
        case regionId
        case region_id
        case cityKey
        case countryCode
        case countryName
        case adminArea
        case cityName
        case aliases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        regionId = try container.decodeIfPresent(String.self, forKey: .regionId)
            ?? container.decodeIfPresent(String.self, forKey: .region_id)
        cityKey = try container.decodeIfPresent(String.self, forKey: .cityKey)
        countryCode = try container.decode(String.self, forKey: .countryCode)
        countryName = try container.decode(String.self, forKey: .countryName)
        adminArea = try container.decodeIfPresent(String.self, forKey: .adminArea)
        cityName = try container.decode(String.self, forKey: .cityName)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }

    var canonicalRegionId: String {
        let rawId = regionId ?? id
        return rawId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .uppercased()
    }
}

nonisolated private struct CityBoundaryGeometry: Decodable {
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
