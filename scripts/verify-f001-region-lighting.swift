import Foundation

struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw VerificationFailure(description: message)
    }
}

func requireEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw VerificationFailure(description: "\(message): expected \(expected), got \(actual)")
    }
}

func rectangle(minLat: Double, maxLat: Double, minLng: Double, maxLng: Double) -> RegionPolygon {
    RegionPolygon(
        exterior: RegionRing(
            coordinates: [
                Coordinate(latitude: minLat, longitude: minLng),
                Coordinate(latitude: minLat, longitude: maxLng),
                Coordinate(latitude: maxLat, longitude: maxLng),
                Coordinate(latitude: maxLat, longitude: minLng),
                Coordinate(latitude: minLat, longitude: minLng)
            ]
        )
    )
}

func region(_ id: String, level: RegionLevel = .city, polygon: RegionPolygon) -> Region {
    Region(
        regionId: id,
        level: level,
        datum: .wgs84,
        bbox: polygon.bbox,
        parentId: nil,
        nameZh: id,
        nameEn: id,
        countryCode: String(id.prefix(2))
    )
}

func verifyChinaGeo() throws {
    let guangzhou = Coordinate(latitude: 23.1291, longitude: 113.2644)
    let shanghai = Coordinate(latitude: 31.2304, longitude: 121.4737)
    let hongKong = Coordinate(latitude: 22.3193, longitude: 114.1694)
    let macao = Coordinate(latitude: 22.1987, longitude: 113.5439)
    let taipei = Coordinate(latitude: 25.0330, longitude: 121.5654)
    let sanFrancisco = Coordinate(latitude: 37.7749, longitude: -122.4194)

    try require(ChinaGeo.isInsideChina(guangzhou), "Guangzhou should be inside mainland China")
    try require(ChinaGeo.isInsideChina(shanghai), "Shanghai should be inside mainland China")
    try require(!ChinaGeo.isInsideChina(hongKong), "Hong Kong should be excluded from mainland China transform")
    try require(!ChinaGeo.isInsideChina(macao), "Macao should be excluded from mainland China transform")
    try require(!ChinaGeo.isInsideChina(taipei), "Taipei should be excluded from mainland China transform")
    try require(!ChinaGeo.isInsideChina(sanFrancisco), "San Francisco should be outside China")

    for coordinate in [guangzhou, shanghai] {
        let gcj = ChinaGeo.wgs84ToGcj02(coordinate)
        let roundTrip = ChinaGeo.gcj02ToWgs84(gcj)
        let error = ChinaGeo.distanceMeters(coordinate, roundTrip)
        try require(error < 1.0, "WGS84/GCJ02 round-trip should be <1m, got \(error)m")
    }

    try requireEqual(OverseasTransform().forDisplay(sanFrancisco), sanFrancisco, "Overseas transform should be identity")
    try requireEqual(ChinaDisplayTransform().forDisplay(hongKong), hongKong, "Hong Kong display transform should be identity")
    try require(ChinaDisplayTransform().forDisplay(guangzhou) != guangzhou, "Mainland display transform should apply GCJ offset")
}

func verifyMatcher() throws {
    let guangzhouPolygon = rectangle(minLat: 22.8, maxLat: 23.4, minLng: 112.8, maxLng: 113.8)
    let shenzhenPolygon = rectangle(minLat: 22.3, maxLat: 22.9, minLng: 113.7, maxLng: 114.6)
    let shinjukuPolygon = rectangle(minLat: 35.66, maxLat: 35.72, minLng: 139.67, maxLng: 139.75)
    let hongKongWest = rectangle(minLat: 22.18, maxLat: 22.38, minLng: 113.9, maxLng: 114.15)
    let hongKongEast = rectangle(minLat: 22.18, maxLat: 22.38, minLng: 114.15, maxLng: 114.45)
    let hongKongRegion = Region(
        regionId: "HK-HONG-KONG",
        level: .city,
        datum: .wgs84,
        bbox: BBox(coordinates: (hongKongWest.exterior.coordinates + hongKongEast.exterior.coordinates)),
        parentId: nil,
        nameZh: "HK-HONG-KONG",
        nameEn: "HK-HONG-KONG",
        countryCode: "HK"
    )
    let holedPolygon = RegionPolygon(
        exterior: RegionRing(
            coordinates: [
                Coordinate(latitude: 0, longitude: 0),
                Coordinate(latitude: 0, longitude: 10),
                Coordinate(latitude: 10, longitude: 10),
                Coordinate(latitude: 10, longitude: 0),
                Coordinate(latitude: 0, longitude: 0)
            ]
        ),
        holes: [
            RegionRing(
                coordinates: [
                    Coordinate(latitude: 4, longitude: 4),
                    Coordinate(latitude: 4, longitude: 6),
                    Coordinate(latitude: 6, longitude: 6),
                    Coordinate(latitude: 6, longitude: 4),
                    Coordinate(latitude: 4, longitude: 4)
                ]
            )
        ]
    )

    let regions = [
        region("CN-440100", polygon: guangzhouPolygon),
        region("CN-440300", polygon: shenzhenPolygon),
        region("JP-13-SHINJUKU", level: .district, polygon: shinjukuPolygon),
        hongKongRegion,
        region("TEST-HOLE", polygon: holedPolygon)
    ]
    let matcher = try RegionMatcher(
        regions: regions,
        geometryByRegionId: [
            "CN-440100": [guangzhouPolygon],
            "CN-440300": [shenzhenPolygon],
            "JP-13-SHINJUKU": [shinjukuPolygon],
            "HK-HONG-KONG": [hongKongWest, hongKongEast],
            "TEST-HOLE": [holedPolygon]
        ],
        bboxPadding: 0
    )

    try requireEqual(matcher.match(Coordinate(latitude: 23.1291, longitude: 113.2644))?.region.regionId, "CN-440100", "Guangzhou point should match Guangzhou")
    try requireEqual(matcher.match(Coordinate(latitude: 22.5431, longitude: 114.0579))?.region.regionId, "CN-440300", "Shenzhen point should match Shenzhen")
    try requireEqual(matcher.match(Coordinate(latitude: 35.6909, longitude: 139.7003))?.region.regionId, "JP-13-SHINJUKU", "Shinjuku point should match Shinjuku")
    try requireEqual(matcher.match(Coordinate(latitude: 22.2855, longitude: 114.30))?.region.regionId, "HK-HONG-KONG", "Hong Kong multipolygon should match east polygon")
    try require(matcher.match(Coordinate(latitude: 23.6, longitude: 114.7)) == nil, "Outside point should not match any city")
    try requireEqual(matcher.match(Coordinate(latitude: 0, longitude: 5))?.region.regionId, "TEST-HOLE", "Boundary point should be inside by V0 edge policy")
    try requireEqual(matcher.match(Coordinate(latitude: 2, longitude: 2))?.region.regionId, "TEST-HOLE", "Point in exterior should match")
    try require(matcher.match(Coordinate(latitude: 5, longitude: 5)) == nil, "Point in hole should not match")
}

func verifyBundledProvider() throws {
    let provider = BundledRegionDataProvider(
        url: URL(fileURLWithPath: "footprint/Data/city_boundaries.geojson")
    )
    let regions = try provider.regions()
    try require(regions.count >= 10, "Bundled starter catalog should contain at least 10 regions")
    try require(regions.allSatisfy { $0.datum == .wgs84 }, "Bundled starter catalog should use WGS-84 canonical datum")
    try require(regions.contains { $0.regionId == "JP-TOKYO-SHINJUKU" }, "Catalog should expose Shinjuku by canonical regionId")

    let matcher = try RegionMatcher(provider: provider, bboxPadding: 0)
    try requireEqual(matcher.match(Coordinate(latitude: 35.6909, longitude: 139.7003))?.region.regionId, "JP-TOKYO-SHINJUKU", "Provider matcher should match Shinjuku")
    try requireEqual(matcher.match(Coordinate(latitude: 37.7749, longitude: -122.4194))?.region.regionId, "US-CA-SAN-FRANCISCO", "Provider matcher should match San Francisco")
}

@main
enum F001Verifier {
    static func main() throws {
        try verifyChinaGeo()
        try verifyMatcher()
        try verifyBundledProvider()
        print("F001 verification passed")
    }
}
