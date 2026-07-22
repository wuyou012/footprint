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
    try require(
        matcher.match(
            Coordinate(latitude: 35.6909, longitude: 139.7003),
            candidateRegionIds: Set(["US-CA-SF"])
        ) == nil,
        "Candidate region IDs should constrain matcher search space"
    )
    try requireEqual(matcher.match(Coordinate(latitude: 22.2855, longitude: 114.30))?.region.regionId, "HK-HONG-KONG", "Hong Kong multipolygon should match east polygon")
    try require(matcher.match(Coordinate(latitude: 23.6, longitude: 114.7)) == nil, "Outside point should not match any city")
    try requireEqual(matcher.match(Coordinate(latitude: 0, longitude: 5))?.region.regionId, "TEST-HOLE", "Boundary point should be inside by V0 edge policy")
    try requireEqual(matcher.match(Coordinate(latitude: 2, longitude: 2))?.region.regionId, "TEST-HOLE", "Point in exterior should match")
    try require(matcher.match(Coordinate(latitude: 5, longitude: 5)) == nil, "Point in hole should not match")
}

func verifyBundledProvider() throws {
    let catalogURL = URL(fileURLWithPath: "footprint/Data/city_boundaries.geojson")
    let provider = BundledRegionDataProvider(url: catalogURL)
    let regions = try provider.regions()
    try requireEqual(regions.count, 48, "Admin1 catalog should contain 47 Japan prefectures plus the SF demo region")
    try require(regions.allSatisfy { $0.datum == .wgs84 }, "Bundled catalog should use WGS-84 canonical datum")
    try require(regions.contains { $0.regionId == "US-CA-SF" }, "Catalog should expose San Francisco by canonical regionId")
    let japanAdmin1 = regions
        .filter { $0.countryCode.uppercased() == "JP" && $0.level == .admin1 }
    try requireEqual(japanAdmin1.count, 47, "Japan catalog should expose all 47 prefectures")
    let expectedPrefectureIds = Set((1...47).map { "JP-\(String(format: "%02d", $0))" })
    try requireEqual(Set(japanAdmin1.map(\.regionId)), expectedPrefectureIds, "Japan prefecture region IDs should be JP-01 through JP-47")

    let hokkaido = try requireRegion(regions, id: "JP-01")
    let tokyo = try requireRegion(regions, id: "JP-13")
    let osaka = try requireRegion(regions, id: "JP-27")
    let okinawa = try requireRegion(regions, id: "JP-47")
    try requireEqual(hokkaido.nameZh, "北海道", "Hokkaido should use the official N03 prefecture name")
    try requireEqual(tokyo.level, .admin1, "Tokyo should be modeled as one admin1 region")
    try requireEqual(tokyo.nameZh, "東京都", "Tokyo admin1 should use Tokyo name")
    try requireEqual(osaka.nameZh, "大阪府", "Osaka should use the official N03 prefecture name")
    try requireEqual(okinawa.nameZh, "沖縄県", "Okinawa should use the official N03 prefecture name")
    try require(!regions.contains { $0.regionId == "JP-13104" }, "Fine-grained Shinjuku region should stay parked behind the ward-level tag")
    try require(!regions.contains { $0.regionId == "JP-13-SHINJUKU" }, "Legacy Shinjuku demo regionId should not return")

    let tokyoAliases = try catalogAliases(in: catalogURL, regionId: "JP-13")
    try require(
        tokyoAliases.contains("jp|东京|東京都"),
        "Tokyo catalog should alias Simplified Chinese CLGeocoder output"
    )

    let sanFranciscoGeometry = try provider.geometry(for: "US-CA-SF")
    let tokyoGeometry = try provider.geometry(for: "JP-13")
    try requireEqual(sanFranciscoGeometry.count, 1, "San Francisco demo boundary should have one polygon")
    try requireEqual(sanFranciscoGeometry[0].exterior.coordinates.count, 100, "San Francisco boundary should keep 100 exterior coordinates")
    try require(tokyoGeometry.count >= 1, "Tokyo should retain at least one polygon")
    try require(tokyoGeometry.count <= 30, "Tokyo admin1 geometry should stay lightweight enough for MapKit")
    let totalJapanPolygons = try japanAdmin1.reduce(0) { partialResult, region in
        partialResult + (try provider.geometry(for: region.regionId).count)
    }
    try require(totalJapanPolygons <= 350, "Japan admin1 geometry should stay lightweight enough for MapKit")

    let matcher = try RegionMatcher(provider: provider, bboxPadding: 0)
    try requireEqual(matcher.match(Coordinate(latitude: 37.7793, longitude: -122.4193))?.region.regionId, "US-CA-SF", "Provider matcher should match the San Francisco demo seed")
    try requireEqual(matcher.match(Coordinate(latitude: 35.6910, longitude: 139.7020))?.region.regionId, "JP-13", "Provider matcher should match Shinjuku to Tokyo")
    try requireEqual(matcher.match(Coordinate(latitude: 35.6581, longitude: 139.7017))?.region.regionId, "JP-13", "Provider matcher should match Shibuya to Tokyo")
    try requireEqual(matcher.match(Coordinate(latitude: 27.0945, longitude: 142.1918))?.region.regionId, "JP-13", "Provider matcher should keep Ogasawara inside Tokyo")
    try requireEqual(matcher.match(Coordinate(latitude: 43.0618, longitude: 141.3545))?.region.regionId, "JP-01", "Provider matcher should match Sapporo to Hokkaido")
    try requireEqual(matcher.match(Coordinate(latitude: 34.6873, longitude: 135.5262))?.region.regionId, "JP-27", "Provider matcher should match Osaka Castle to Osaka")
    try requireEqual(matcher.match(Coordinate(latitude: 26.2124, longitude: 127.6809))?.region.regionId, "JP-47", "Provider matcher should match Naha to Okinawa")
    try require(matcher.match(Coordinate(latitude: 34.0522, longitude: -118.2437)) == nil, "Provider matcher should not match a far outside point")
}

func requireRegion(_ regions: [Region], id: String) throws -> Region {
    guard let region = regions.first(where: { $0.regionId == id }) else {
        throw VerificationFailure(description: "Expected catalog to contain \(id)")
    }
    return region
}

func catalogAliases(in url: URL, regionId: String) throws -> [String] {
    let data = try Data(contentsOf: url)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let features = root["features"] as? [[String: Any]]
    else { return [] }

    for feature in features {
        guard let properties = feature["properties"] as? [String: Any],
              properties["region_id"] as? String == regionId
        else { continue }
        return properties["aliases"] as? [String] ?? []
    }
    return []
}

func mapCity(
    id: String,
    countryCode: String,
    countryName: String,
    cityName: String,
    minLatitude: Double,
    maxLatitude: Double,
    minLongitude: Double,
    maxLongitude: Double,
    unlocked: Bool
) -> RegionAchievementMapCity {
    RegionAchievementMapCity(
        cityKey: id,
        regionId: id,
        countryCode: countryCode,
        countryName: countryName,
        adminArea: nil,
        cityName: cityName,
        minLatitude: minLatitude,
        maxLatitude: maxLatitude,
        minLongitude: minLongitude,
        maxLongitude: maxLongitude,
        cellCount: unlocked ? 1 : 0,
        colorIndex: 0,
        isUnlocked: unlocked,
        cityKeyAliases: [],
        boundaryPolygons: []
    )
}

func verifyMapViewportFiltering() throws {
    let sanFrancisco = mapCity(
        id: "US-CA-SF",
        countryCode: "us",
        countryName: "United States",
        cityName: "San Francisco",
        minLatitude: 37.70,
        maxLatitude: 37.84,
        minLongitude: -122.53,
        maxLongitude: -122.35,
        unlocked: true
    )
    let oakland = mapCity(
        id: "US-CA-OAK",
        countryCode: "US",
        countryName: "United States",
        cityName: "Oakland",
        minLatitude: 37.70,
        maxLatitude: 37.88,
        minLongitude: -122.31,
        maxLongitude: -122.12,
        unlocked: false
    )
    let shinjuku = mapCity(
        id: "JP-13-SHINJUKU",
        countryCode: "jp",
        countryName: "Japan",
        cityName: "Shinjuku",
        minLatitude: 35.67,
        maxLatitude: 35.73,
        minLongitude: 139.67,
        maxLongitude: 139.75,
        unlocked: true
    )
    let ogasawara = mapCity(
        id: "JP-13421",
        countryCode: "JP",
        countryName: "Japan",
        cityName: "Ogasawara",
        minLatitude: 26.6,
        maxLatitude: 27.2,
        minLongitude: 142.0,
        maxLongitude: 142.4,
        unlocked: false
    )

    let countries = RegionAchievementMapCountryOption.options(for: [sanFrancisco, shinjuku, oakland])
    try requireEqual(countries.map(\.countryCode), ["JP", "US"], "Country options should be normalized and sorted")
    try requireEqual(countries.first(where: { $0.countryCode == "US" })?.regionCount, 2, "US country option should count both US cities")
    try requireEqual(countries.first(where: { $0.countryCode == "US" })?.unlockedCount, 1, "US country option should count unlocked cities")

    let bayViewport = RegionAchievementMapViewport(
        centerLatitude: 37.78,
        centerLongitude: -122.27,
        latitudeDelta: 0.35,
        longitudeDelta: 0.45
    )
    let visibleUS = RegionAchievementMapFilter.visibleCities(
        in: [sanFrancisco, shinjuku, oakland],
        countryCode: "us",
        viewport: bayViewport
    )
    try requireEqual(Set(visibleUS.map(\.cityKey)), Set(["US-CA-SF", "US-CA-OAK"]), "Bay viewport should include only US cities in view")

    let outsideViewport = RegionAchievementMapViewport(
        centerLatitude: 0,
        centerLongitude: 0,
        latitudeDelta: 0.5,
        longitudeDelta: 0.5
    )
    try require(
        RegionAchievementMapFilter.visibleCities(
            in: [sanFrancisco, shinjuku, oakland],
            countryCode: "US",
            viewport: outsideViewport
        ).isEmpty,
        "Viewport culling should not fall back to drawing a whole country when the viewport is outside it"
    )

    let tokyoViewport = RegionAchievementMapViewport(
        centerLatitude: 35.70,
        centerLongitude: 139.71,
        latitudeDelta: 0.12,
        longitudeDelta: 0.12
    )
    let visibleJapan = RegionAchievementMapFilter.visibleCities(
        in: [sanFrancisco, shinjuku, oakland],
        countryCode: "JP",
        viewport: tokyoViewport
    )
    try requireEqual(visibleJapan.map(\.cityKey), ["JP-13-SHINJUKU"], "Tokyo viewport should include Shinjuku only")

    let overviewJapan = RegionAchievementMapFilter.overviewCities(in: [shinjuku, ogasawara])
    try requireEqual(overviewJapan.map(\.cityKey), ["JP-13-SHINJUKU"], "Tokyo default overview should exclude remote islands")
}

#if DEBUG
func verifyDemoSeeds() throws {
    let provider = BundledRegionDataProvider(
        url: URL(fileURLWithPath: "footprint/Data/city_boundaries.geojson")
    )
    let matcher = try RegionMatcher(provider: provider, bboxPadding: 0)

    try requireEqual(RegionAchievementDemoSeeds.points.count, 2, "V0 demo should seed exactly two track points")
    for seed in RegionAchievementDemoSeeds.points {
        try requireEqual(
            matcher.match(seed.coordinate)?.region.regionId,
            seed.regionId,
            "Demo seed should fall inside its target region"
        )
    }
}
#endif

@main
enum F001Verifier {
    static func main() throws {
        try verifyChinaGeo()
        try verifyMatcher()
        try verifyMapViewportFiltering()
        try verifyBundledProvider()
        #if DEBUG
        try verifyDemoSeeds()
        #endif
        print("F001 verification passed")
    }
}
