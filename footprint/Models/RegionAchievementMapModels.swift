import Foundation

nonisolated struct RegionAchievementMapViewport: Hashable, Sendable {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double

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
