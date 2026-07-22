import Foundation

nonisolated struct BundledRegionDataProvider: RegionDataProvider {
    enum ProviderError: Error {
        case missingResource
        case missingGeometry(String)
    }

    private let loader: @Sendable () throws -> Data

    init(resourceName: String = "city_boundaries", resourceExtension: String = "geojson") {
        loader = {
            guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) else {
                throw ProviderError.missingResource
            }
            return try Data(contentsOf: url)
        }
    }

    init(url: URL) {
        loader = {
            try Data(contentsOf: url)
        }
    }

    func regions() throws -> [Region] {
        try decodedFeatures().map { feature in
            let polygons = feature.geometry.regionPolygons
            let coordinates = polygons.flatMap { $0.exterior.coordinates }
            let regionId = feature.properties.canonicalRegionId
            return Region(
                regionId: regionId,
                level: feature.properties.regionLevel,
                datum: .wgs84,
                bbox: BBox(coordinates: coordinates),
                parentId: feature.properties.parentId,
                nameZh: feature.properties.resolvedNameZh,
                nameEn: feature.properties.resolvedNameEn,
                countryCode: feature.properties.countryCode.uppercased()
            )
        }
    }

    func geometry(for regionId: String) throws -> [RegionPolygon] {
        let normalizedId = regionId.uppercased()
        guard let feature = try decodedFeatures().first(where: { $0.properties.canonicalRegionId == normalizedId }) else {
            throw ProviderError.missingGeometry(regionId)
        }
        return feature.geometry.regionPolygons
    }

    func catalogFingerprint() throws -> String {
        let data = try loader()
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private func decodedFeatures() throws -> [RegionBoundaryFeature] {
        try JSONDecoder().decode(RegionFeatureCollection.self, from: loader()).features
    }
}

nonisolated private struct RegionFeatureCollection: Decodable {
    let features: [RegionBoundaryFeature]
}

nonisolated private struct RegionBoundaryFeature: Decodable {
    let properties: RegionBoundaryProperties
    let geometry: RegionBoundaryGeometry
}

nonisolated private struct RegionBoundaryProperties: Decodable {
    let id: String
    let regionId: String?
    let level: String?
    let parentId: String?
    let countryCode: String
    let countryName: String
    let adminArea: String?
    let cityName: String
    let rawNameZh: String?
    let rawNameEn: String?

    enum CodingKeys: CodingKey {
        case id
        case regionId
        case region_id
        case level
        case parentId
        case parent_id
        case countryCode
        case countryName
        case adminArea
        case cityName
        case nameZh
        case nameEn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        regionId = try container.decodeIfPresent(String.self, forKey: .regionId)
            ?? container.decodeIfPresent(String.self, forKey: .region_id)
        level = try container.decodeIfPresent(String.self, forKey: .level)
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
            ?? container.decodeIfPresent(String.self, forKey: .parent_id)
        countryCode = try container.decode(String.self, forKey: .countryCode)
        countryName = try container.decode(String.self, forKey: .countryName)
        adminArea = try container.decodeIfPresent(String.self, forKey: .adminArea)
        cityName = try container.decode(String.self, forKey: .cityName)
        rawNameZh = try container.decodeIfPresent(String.self, forKey: .nameZh)
        rawNameEn = try container.decodeIfPresent(String.self, forKey: .nameEn)
    }

    var canonicalRegionId: String {
        let rawId = regionId ?? id
        return rawId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .uppercased()
    }

    var regionLevel: RegionLevel {
        switch level?.lowercased() {
        case "country": .country
        case "admin1": .admin1
        case "district": .district
        default: .city
        }
    }

    var resolvedNameZh: String {
        rawNameZh ?? cityName
    }

    var resolvedNameEn: String {
        rawNameEn ?? cityName
    }
}

nonisolated private struct RegionBoundaryGeometry: Decodable {
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
            polygons = [try container.decode([[[Double]]].self, forKey: .coordinates)]
        case "MultiPolygon":
            polygons = try container.decode([[[[Double]]]].self, forKey: .coordinates)
        default:
            polygons = []
        }
    }

    var regionPolygons: [RegionPolygon] {
        polygons.compactMap { rings in
            guard let exterior = rings.first.map(regionRing), exterior.coordinates.count >= 3 else {
                return nil
            }
            let holes = rings.dropFirst()
                .map(regionRing)
                .filter { $0.coordinates.count >= 3 }
            return RegionPolygon(exterior: exterior, holes: holes)
        }
    }

    private func regionRing(_ ring: [[Double]]) -> RegionRing {
        RegionRing(
            coordinates: ring.compactMap { pair in
                guard pair.count >= 2 else { return nil }
                return Coordinate(latitude: pair[1], longitude: pair[0])
            }
        )
    }
}
