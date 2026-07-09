import Combine
import MapKit
import SwiftUI

struct RegionAchievementMapView: View {
    @StateObject private var model = RegionAchievementMapViewModel()
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedCountryCode: String?
    @State private var selectedCityID: String?
    @State private var visibleViewport: RegionAchievementMapViewport?

    var body: some View {
        Group {
            if model.loading && model.cities.isEmpty {
                ProgressView("Loading city map")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.cities.isEmpty {
                ContentUnavailableView(
                    "No city regions",
                    systemImage: "map",
                    description: Text("No city boundary data is available.")
                )
            } else {
                ZStack(alignment: .bottom) {
                    map
                    mapLegend
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle("City Map")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
        .task {
            await model.load()
            let launchFocusedCity = Self.launchFocusCity(in: model.cities)
            let focusedCity = launchFocusedCity
                ?? Self.focusedCity(in: model.cities, focus: model.focusCoordinate?.coordinate)
            selectedCountryCode = focusedCity?.countryCodeKey ?? Self.defaultCountryCode(in: model.cities)
            selectedCityID = focusedCity?.id
            if let launchFocusedCity {
                let targetRegion = Self.region(for: [launchFocusedCity], focus: nil)
                visibleViewport = Self.viewport(for: targetRegion)
                position = .region(targetRegion)
            } else {
                let countryCities = RegionAchievementMapFilter.countryCities(
                    in: model.cities,
                    countryCode: selectedCountryCode
                )
                let targetRegion = Self.region(
                    for: RegionAchievementMapFilter.overviewCities(in: countryCities),
                    focus: model.focusCoordinate?.coordinate
                )
                visibleViewport = Self.viewport(for: targetRegion)
                position = .region(targetRegion)
            }
        }
    }

    private var map: some View {
        Map(position: $position) {
            ForEach(visibleCities) { city in
                ForEach(city.mapBoundaryPolygons) { boundary in
                    MapPolygon(coordinates: boundary.mapCoordinates)
                        .foregroundStyle(Self.fillColor(for: city).opacity(Self.fillOpacity(for: city)))

                    MapPolyline(coordinates: boundary.closedMapCoordinates)
                        .stroke(Self.strokeColor(for: city).opacity(city.isUnlocked ? 0.62 : 0.18), lineWidth: city.isUnlocked ? 6.2 : 1.8)

                    MapPolyline(coordinates: boundary.closedMapCoordinates)
                        .stroke(Self.strokeColor(for: city).opacity(city.isUnlocked ? 0.98 : 0.42), lineWidth: city.isUnlocked ? 2.5 : 0.8)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .environment(\.colorScheme, .dark)
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleViewport = Self.viewport(for: context.region)
        }
    }

    private var mapLegend: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                LegendItem(label: "City boundary", color: Self.cityBoundaryColor, symbol: .stroke)
                LegendItem(label: "No track", color: Self.cityInteriorColor, symbol: .fill)
                LegendItem(label: "Track found", color: Self.awardUnlockedColor, symbol: .fill)
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(countryOptions) { country in
                        Button {
                            selectedCountryCode = country.countryCode
                            selectedCityID = nil
                            let countryCities = RegionAchievementMapFilter.countryCities(
                                in: model.cities,
                                countryCode: country.countryCode
                            )
                            let targetRegion = Self.region(
                                for: RegionAchievementMapFilter.overviewCities(in: countryCities),
                                focus: nil
                            )
                            visibleViewport = Self.viewport(for: targetRegion)
                            withAnimation(.easeInOut(duration: 0.25)) {
                                position = .region(targetRegion)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(country.countryCode)
                                    .font(.caption.weight(.black))
                                    .monospaced()
                                Text("\(country.unlockedCount)/\(country.regionCount)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(.ultraThinMaterial)
                            .overlay {
                                if selectedCountryCode == country.countryCode {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Self.cityBoundaryColor.opacity(0.9), lineWidth: 1.5)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(selectedCountryCities) { city in
                        Button {
                            selectedCityID = city.id
                            let targetRegion = Self.region(for: [city], focus: nil)
                            visibleViewport = Self.viewport(for: targetRegion)
                            withAnimation(.easeInOut(duration: 0.25)) {
                                position = .region(targetRegion)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(city.isUnlocked ? Self.awardUnlockedColor : Self.cityInteriorColor)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(city.cityName)
                                        .font(.caption.weight(.bold))
                                    Text(city.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(.ultraThinMaterial)
                            .overlay {
                                if selectedCityID == city.id {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Self.awardUnlockedColor.opacity(0.9), lineWidth: 1.5)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 10)
    }

    private var countryOptions: [RegionAchievementMapCountryOption] {
        RegionAchievementMapCountryOption.options(for: model.cities)
    }

    private var selectedCountryCities: [RegionAchievementMapCity] {
        RegionAchievementMapFilter.countryCities(
            in: model.cities,
            countryCode: selectedCountryCode
        )
    }

    private var visibleCities: [RegionAchievementMapCity] {
        RegionAchievementMapFilter.visibleCities(
            in: model.cities,
            countryCode: selectedCountryCode,
            viewport: visibleViewport
        )
    }

    private static func region(
        for cities: [RegionAchievementMapCity],
        focus: CLLocationCoordinate2D?
    ) -> MKCoordinateRegion {
        let regionCities = citiesInInitialCluster(cities, focus: focus)
        guard let first = regionCities.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }

        var minLatitude = first.minLatitude
        var maxLatitude = first.maxLatitude
        var minLongitude = first.minLongitude
        var maxLongitude = first.maxLongitude

        for city in regionCities.dropFirst() {
            minLatitude = min(minLatitude, city.minLatitude)
            maxLatitude = max(maxLatitude, city.maxLatitude)
            minLongitude = min(minLongitude, city.minLongitude)
            maxLongitude = max(maxLongitude, city.maxLongitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.03, (maxLatitude - minLatitude) * 1.45),
                longitudeDelta: max(0.03, (maxLongitude - minLongitude) * 1.45)
            )
        )
    }

    private static let cityBoundaryColor = Color(red: 0.21, green: 0.96, blue: 1.00)
    private static let cityInteriorColor = Color(red: 0.04, green: 0.56, blue: 0.66)
    private static let awardUnlockedColor = Color(red: 1.00, green: 0.72, blue: 0.12)

    private static func fillColor(for city: RegionAchievementMapCity) -> Color {
        city.isUnlocked ? awardUnlockedColor : cityInteriorColor
    }

    private static func strokeColor(for city: RegionAchievementMapCity) -> Color {
        city.isUnlocked ? awardUnlockedColor : cityBoundaryColor
    }

    private static func fillOpacity(for city: RegionAchievementMapCity) -> Double {
        city.isUnlocked ? 0.46 : 0.05
    }

    private static func citiesInInitialCluster(
        _ cities: [RegionAchievementMapCity],
        focus: CLLocationCoordinate2D?
    ) -> [RegionAchievementMapCity] {
        guard let focus else { return cities }
        let nearbyCities = cities.filter { city in
            abs(city.centerCoordinate.latitude - focus.latitude) <= 1.2
                && longitudeDistance(city.centerCoordinate.longitude, focus.longitude) <= 1.2
        }
        return nearbyCities.isEmpty ? cities : nearbyCities
    }

    private static func longitudeDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let rawDistance = abs(lhs - rhs)
        return min(rawDistance, 360 - rawDistance)
    }

    private static func focusedCity(
        in cities: [RegionAchievementMapCity],
        focus: CLLocationCoordinate2D?
    ) -> RegionAchievementMapCity? {
        guard let focus else {
            return cities.first(where: \.isUnlocked) ?? cities.first
        }
        return cities.min { lhs, rhs in
            let lhsDistance = abs(lhs.centerCoordinate.latitude - focus.latitude)
                + longitudeDistance(lhs.centerCoordinate.longitude, focus.longitude)
            let rhsDistance = abs(rhs.centerCoordinate.latitude - focus.latitude)
                + longitudeDistance(rhs.centerCoordinate.longitude, focus.longitude)
            return lhsDistance < rhsDistance
        }
    }

    private static func launchFocusCity(
        in cities: [RegionAchievementMapCity]
    ) -> RegionAchievementMapCity? {
        #if DEBUG
        let prefix = "--region-achievement-focus="
        guard let rawArgument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        let regionId = String(rawArgument.dropFirst(prefix.count)).uppercased()
        return cities.first { $0.normalizedRegionId == regionId }
        #else
        return nil
        #endif
    }

    private static func defaultCountryCode(in cities: [RegionAchievementMapCity]) -> String? {
        let countryOptions = RegionAchievementMapCountryOption.options(for: cities)
        return countryOptions.first(where: { $0.unlockedCount > 0 })?.countryCode
            ?? countryOptions.first?.countryCode
    }

    private static func viewport(for region: MKCoordinateRegion) -> RegionAchievementMapViewport {
        RegionAchievementMapViewport(
            centerLatitude: region.center.latitude,
            centerLongitude: region.center.longitude,
            latitudeDelta: region.span.latitudeDelta,
            longitudeDelta: region.span.longitudeDelta
        )
    }
}

private struct LegendItem: View {
    enum Symbol {
        case fill
        case stroke
    }

    let label: String
    let color: Color
    let symbol: Symbol

    var body: some View {
        HStack(spacing: 6) {
            legendSymbol
                .frame(width: 12, height: 12)
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var legendSymbol: some View {
        switch symbol {
        case .fill:
            Circle()
                .fill(color)
        case .stroke:
            Circle()
                .stroke(color, lineWidth: 2)
        }
    }
}

@MainActor
private final class RegionAchievementMapViewModel: ObservableObject {
    @Published var cities: [RegionAchievementMapCity] = []
    @Published var focusCoordinate: RegionAchievementBoundaryCoordinate?
    @Published var loading = true
    @Published var errorMessage: String?

    private let service = RegionAchievementService()

    func load() async {
        loading = true
        errorMessage = nil
        do {
            cities = try await service.loadAvailableMapCities()
            focusCoordinate = try await service.loadLastTrackMapFocus()
        } catch {
            errorMessage = AppFormatters.errorMessage(error)
        }
        loading = false
    }
}
