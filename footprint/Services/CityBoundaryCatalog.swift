import Foundation

struct CityBoundaryCatalog: Sendable {
    enum CatalogError: Error {
        case missingResource
    }

    private let resourceName = "city_boundaries"
    private let resourceExtension = "geojson"

    nonisolated init() {}

    nonisolated func loadCities() throws -> [RegionAchievementMapCity] {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) else {
            throw CatalogError.missingResource
        }

        let data = try Data(contentsOf: url)
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
    let cityKey: String?
    let countryCode: String
    let countryName: String
    let adminArea: String?
    let cityName: String
    let aliases: [String]

    enum CodingKeys: CodingKey {
        case id
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
        cityKey = try container.decodeIfPresent(String.self, forKey: .cityKey)
        countryCode = try container.decode(String.self, forKey: .countryCode)
        countryName = try container.decode(String.self, forKey: .countryName)
        adminArea = try container.decodeIfPresent(String.self, forKey: .adminArea)
        cityName = try container.decode(String.self, forKey: .cityName)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
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
