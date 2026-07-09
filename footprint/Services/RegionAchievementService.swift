import CoreLocation
import Foundation

actor RegionAchievementService {
    private let store = TrackDatabase.shared
    private let geocoder = CLGeocoder()
    private let cityBoundaryCatalog = CityBoundaryCatalog()

    func loadCountries() throws -> [RegionAchievementCountry] {
        try store.loadRegionAchievements()
    }

    func loadMapCities() throws -> [RegionAchievementMapCity] {
        try store.loadRegionAchievementMapCities()
    }

    func loadAvailableMapCities() throws -> [RegionAchievementMapCity] {
        let unlockedCities = try store.loadRegionAchievementMapCities()
        let catalogCities: [RegionAchievementMapCity]
        do {
            catalogCities = try cityBoundaryCatalog.loadCities()
        } catch CityBoundaryCatalog.CatalogError.missingResource {
            return unlockedCities
        }

        let trackRegionPointCounts = try loadTrackRegionPointCounts()
        let adminCoverageKeys = Self.adminCoverageKeys(for: catalogCities)
        var unlockedByKey: [String: RegionAchievementMapCity] = [:]
        for city in unlockedCities {
            for key in city.matchKeys {
                unlockedByKey[key] = city
            }
        }

        var catalogKeys = Set<String>()
        var mergedCities = catalogCities.map { city in
            city.matchKeys.forEach { catalogKeys.insert($0) }
            if let regionId = city.normalizedRegionId,
               let pointCount = trackRegionPointCounts[regionId] {
                return city.applyingTrackUnlock(pointCount: pointCount)
            }
            guard let unlockedCity = city.matchKeys.compactMap({ unlockedByKey[$0] }).first else {
                return city
            }
            return city.applyingUnlock(from: unlockedCity)
        }

        let fallbackUnlockedCities = unlockedCities.filter { city in
            !city.matchKeys.contains { catalogKeys.contains($0) }
                && !Self.isCoveredByAdminCatalog(city, coverageKeys: adminCoverageKeys)
        }
        mergedCities.append(contentsOf: fallbackUnlockedCities)

        return Self.sortedMapCities(mergedCities)
    }

    func loadLastTrackMapFocus() throws -> RegionAchievementBoundaryCoordinate? {
        guard let point = try store.loadLastTrackPoint() else { return nil }
        return RegionAchievementBoundaryCoordinate(
            latitude: point.latitude,
            longitude: point.longitude
        )
    }

    func syncNextBatch(limit: Int = 28) async throws -> RegionAchievementSyncResult {
        let safeLimit = max(1, min(60, limit))
        let candidates = try store.loadPendingRegionAchievementCells(limit: safeLimit)
        guard !candidates.isEmpty else {
            return RegionAchievementSyncResult(
                scannedCells: 0,
                resolvedCells: 0,
                newCities: 0,
                hasMore: false
            )
        }

        var resolvedCells = 0
        var newCities = 0

        for candidate in candidates {
            let place: RegionAchievementResolvedPlace?
            do {
                place = try await resolvePlace(for: candidate)
            } catch {
                continue
            }
            let inserted = try store.saveRegionAchievementCell(candidate, place: place)
            if place != nil {
                resolvedCells += 1
            }
            if inserted {
                newCities += 1
            }
        }

        let hasMore = try store.hasPendingRegionAchievementCells()
        return RegionAchievementSyncResult(
            scannedCells: candidates.count,
            resolvedCells: resolvedCells,
            newCities: newCities,
            hasMore: hasMore
        )
    }

    func clear() throws {
        try store.clearRegionAchievements()
    }

    private func resolvePlace(for candidate: RegionAchievementCandidateCell) async throws -> RegionAchievementResolvedPlace? {
        let placemarks = try await geocoder.reverseGeocodeLocation(candidate.location)
        guard let placemark = placemarks.first else { return nil }
        return Self.place(from: placemark)
    }

    private func loadTrackRegionPointCounts() throws -> [String: Int] {
        let samples = try store.loadRegionAchievementTrackSamples()
        guard !samples.isEmpty else { return [:] }

        let provider = BundledRegionDataProvider()
        let regions = try provider.regions()
        var geometryByRegionId: [String: [RegionPolygon]] = [:]
        for region in regions {
            geometryByRegionId[region.regionId] = try provider.geometry(for: region.regionId)
        }
        try store.replaceRegionCatalogIfNeeded(
            catalogKey: "city_boundaries",
            fingerprint: try provider.catalogFingerprint(),
            regions: regions,
            geometryByRegionId: geometryByRegionId
        )

        let catalog = try store.loadRegionCatalog()
        let matcher = try RegionMatcher(
            regions: catalog.regions,
            geometryByRegionId: catalog.geometryByRegionId
        )
        var pointCountsByRegionId: [String: Int] = [:]

        for sample in samples {
            guard Self.shouldUse(sample) else { continue }
            guard let match = matcher.match(sample.coordinate) else { continue }
            pointCountsByRegionId[match.region.regionId, default: 0] += max(1, sample.pointCount)
        }

        return pointCountsByRegionId
    }

    private static func shouldUse(_ sample: RegionAchievementTrackCoordinate) -> Bool {
        guard let accuracy = sample.accuracy else { return true }
        return accuracy <= 500
    }

    private static func place(from placemark: CLPlacemark) -> RegionAchievementResolvedPlace? {
        let countryCode = normalizedKey(placemark.isoCountryCode ?? placemark.country)
        guard !countryCode.isEmpty else { return nil }

        let countryName = clean(placemark.country) ?? countryCode
        let adminArea = clean(placemark.administrativeArea)
        guard let cityName = clean(placemark.locality)
            ?? clean(placemark.subAdministrativeArea)
            ?? adminArea
        else { return nil }

        let cityKey = [
            countryCode,
            normalizedKey(adminArea),
            normalizedKey(cityName)
        ].joined(separator: "|")

        return RegionAchievementResolvedPlace(
            countryCode: countryCode,
            countryName: countryName,
            adminArea: adminArea,
            cityName: cityName,
            cityKey: cityKey
        )
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    private static func normalizedKey(_ value: String?) -> String {
        clean(value)?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "|", with: " ")
        ?? ""
    }

    private static func adminCoverageKeys(for catalogCities: [RegionAchievementMapCity]) -> Set<String> {
        var keys = Set<String>()
        for city in catalogCities where city.normalizedRegionId == "JP-13" {
            let aliases = [
                city.adminArea,
                city.cityName,
                "東京都",
                "東京",
                "东京",
                "tokyo"
            ]
            for alias in aliases {
                let normalizedAlias = normalizedKey(alias)
                if !normalizedAlias.isEmpty {
                    keys.insert("\(city.countryCodeKey)|\(normalizedAlias)")
                }
            }
        }
        return keys
    }

    private static func isCoveredByAdminCatalog(
        _ city: RegionAchievementMapCity,
        coverageKeys: Set<String>
    ) -> Bool {
        guard let adminArea = city.adminArea else { return false }
        return coverageKeys.contains("\(city.countryCodeKey)|\(normalizedKey(adminArea))")
    }

    private static func sortedMapCities(_ cities: [RegionAchievementMapCity]) -> [RegionAchievementMapCity] {
        cities.sorted { lhs, rhs in
            if lhs.isUnlocked != rhs.isUnlocked {
                return lhs.isUnlocked && !rhs.isUnlocked
            }
            if lhs.countryName != rhs.countryName {
                return lhs.countryName < rhs.countryName
            }
            if lhs.adminArea != rhs.adminArea {
                return (lhs.adminArea ?? "") < (rhs.adminArea ?? "")
            }
            return lhs.cityName < rhs.cityName
        }
    }
}
