import Foundation

nonisolated struct RegionAchievementMapViewport: Hashable, Sendable {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double

    var latitudeDelta: Double { maxLatitude - minLatitude }
    var longitudeDelta: Double { maxLongitude - minLongitude }

    init(
        centerLatitude: Double,
        centerLongitude: Double,
        latitudeDelta: Double,
        longitudeDelta: Double
    ) {
        let latitudeRadius = max(0, latitudeDelta) / 2
        let longitudeRadius = max(0, longitudeDelta) / 2
        minLatitude = max(-90, centerLatitude - latitudeRadius)
        maxLatitude = min(90, centerLatitude + latitudeRadius)
        minLongitude = max(-180, centerLongitude - longitudeRadius)
        maxLongitude = min(180, centerLongitude + longitudeRadius)
    }

    func intersects(
        minLatitude otherMinLatitude: Double,
        maxLatitude otherMaxLatitude: Double,
        minLongitude otherMinLongitude: Double,
        maxLongitude otherMaxLongitude: Double,
        padding: Double = 0
    ) -> Bool {
        otherMaxLatitude >= minLatitude - padding
            && otherMinLatitude <= maxLatitude + padding
            && otherMaxLongitude >= minLongitude - padding
            && otherMinLongitude <= maxLongitude + padding
    }
}

nonisolated enum RegionAchievementMapOverlayLimiter {
    static let defaultMaxRenderedRegions = 420

    private static let broadLatitudeDelta = 45.0
    private static let broadLongitudeDelta = 90.0
    private static let viewportPaddingMultiplier = 0.08
    private static let minimumViewportPadding = 0.05
    private static let maximumViewportPadding = 8.0

    static func visibleCities(
        in cities: [RegionAchievementMapCity],
        countryCode: String?,
        viewport: RegionAchievementMapViewport?,
        maxRenderedRegions: Int = defaultMaxRenderedRegions
    ) -> [RegionAchievementMapCity] {
        let scopedCities = RegionAchievementMapFilter.countryCities(in: cities, countryCode: countryCode)
        let safeLimit = max(0, maxRenderedRegions)
        guard safeLimit > 0 else { return [] }
        guard let viewport else {
            return cappedPrioritized(RegionAchievementMapFilter.overviewCities(in: scopedCities), max: safeLimit)
        }

        let intersectingCities = scopedCities.filter { city in
            city.intersects(viewport, padding: padding(for: viewport))
        }
        let eligibleCities = isBroad(viewport)
            ? intersectingCities.filter(\.isUnlocked)
            : intersectingCities
        return cappedPrioritized(eligibleCities, max: safeLimit)
    }

    private static func isBroad(_ viewport: RegionAchievementMapViewport) -> Bool {
        viewport.latitudeDelta > broadLatitudeDelta
            || viewport.longitudeDelta > broadLongitudeDelta
    }

    private static func padding(for viewport: RegionAchievementMapViewport) -> Double {
        min(
            maximumViewportPadding,
            max(minimumViewportPadding, max(viewport.latitudeDelta, viewport.longitudeDelta) * viewportPaddingMultiplier)
        )
    }

    private static func cappedPrioritized(
        _ cities: [RegionAchievementMapCity],
        max limit: Int
    ) -> [RegionAchievementMapCity] {
        Array(cities.sorted(by: overlayPriority).prefix(limit))
    }

    private static func overlayPriority(
        lhs: RegionAchievementMapCity,
        rhs: RegionAchievementMapCity
    ) -> Bool {
        if lhs.isUnlocked != rhs.isUnlocked {
            return lhs.isUnlocked && !rhs.isUnlocked
        }
        if lhs.countryCodeKey != rhs.countryCodeKey {
            return lhs.countryCodeKey < rhs.countryCodeKey
        }
        return lhs.cityKey < rhs.cityKey
    }
}

nonisolated struct RegionAchievementMapCountryOption: Identifiable, Hashable, Sendable {
    let countryCode: String
    let countryName: String
    let regionCount: Int
    let unlockedCount: Int

    var id: String { countryCode }

    static func options(for cities: [RegionAchievementMapCity]) -> [RegionAchievementMapCountryOption] {
        var grouped: [String: (name: String, regionCount: Int, unlockedCount: Int)] = [:]
        for city in cities {
            let code = city.countryCodeKey
            guard !code.isEmpty else { continue }
            var current = grouped[code] ?? (city.countryName, 0, 0)
            current.regionCount += 1
            if city.isUnlocked {
                current.unlockedCount += 1
            }
            grouped[code] = current
        }

        return grouped.map { countryCode, value in
            RegionAchievementMapCountryOption(
                countryCode: countryCode,
                countryName: value.name,
                regionCount: value.regionCount,
                unlockedCount: value.unlockedCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.countryName != rhs.countryName {
                return lhs.countryName.localizedCaseInsensitiveCompare(rhs.countryName) == .orderedAscending
            }
            return lhs.countryCode < rhs.countryCode
        }
    }
}

nonisolated enum RegionAchievementMapFilter {
    private static let tokyoIslandRegionIds: Set<String> = [
        "JP-13361",
        "JP-13362",
        "JP-13363",
        "JP-13364",
        "JP-13381",
        "JP-13382",
        "JP-13401",
        "JP-13402",
        "JP-13421"
    ]

    static func countryCities(
        in cities: [RegionAchievementMapCity],
        countryCode: String?
    ) -> [RegionAchievementMapCity] {
        guard let countryCode, !countryCode.isEmpty else { return cities }
        let normalizedCountryCode = normalizeCountryCode(countryCode)
        return cities.filter { $0.countryCodeKey == normalizedCountryCode }
    }

    static func visibleCities(
        in cities: [RegionAchievementMapCity],
        countryCode: String?,
        viewport: RegionAchievementMapViewport?
    ) -> [RegionAchievementMapCity] {
        let countryScopedCities = countryCities(in: cities, countryCode: countryCode)
        guard let viewport else { return countryScopedCities }
        return countryScopedCities.filter { $0.intersects(viewport) }
    }

    static func overviewCities(in cities: [RegionAchievementMapCity]) -> [RegionAchievementMapCity] {
        let mainlandCities = cities.filter { city in
            guard city.countryCodeKey == "JP",
                  let regionId = city.normalizedRegionId,
                  regionId.hasPrefix("JP-13")
            else { return true }
            return !tokyoIslandRegionIds.contains(regionId)
        }
        return mainlandCities.isEmpty ? cities : mainlandCities
    }

    static func normalizeCountryCode(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}

extension RegionAchievementMapCity {
    nonisolated var countryCodeKey: String {
        RegionAchievementMapFilter.normalizeCountryCode(countryCode)
    }

    nonisolated func intersects(_ viewport: RegionAchievementMapViewport, padding: Double = 0) -> Bool {
        viewport.intersects(
            minLatitude: minLatitude,
            maxLatitude: maxLatitude,
            minLongitude: minLongitude,
            maxLongitude: maxLongitude,
            padding: padding
        )
    }
}
