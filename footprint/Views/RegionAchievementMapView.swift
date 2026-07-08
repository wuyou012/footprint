import Combine
import MapKit
import SwiftUI

struct RegionAchievementMapView: View {
    @StateObject private var model = RegionAchievementMapViewModel()
    @State private var position: MapCameraPosition = .automatic

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
            position = .region(Self.region(for: model.cities, focus: model.focusCoordinate?.coordinate))
        }
    }

    private var map: some View {
        Map(position: $position) {
            ForEach(model.cities) { city in
                ForEach(city.mapBoundaryPolygons) { boundary in
                    MapPolygon(coordinates: boundary.mapCoordinates)
                        .foregroundStyle(Self.fillColor(for: city).opacity(Self.fillOpacity(for: city)))

                    MapPolyline(coordinates: boundary.closedMapCoordinates)
                        .stroke(Self.cityBoundaryColor.opacity(city.isUnlocked ? 0.80 : 0.54), lineWidth: city.isUnlocked ? 5.5 : 3.5)

                    MapPolyline(coordinates: boundary.closedMapCoordinates)
                        .stroke(Self.cityBoundaryColor.opacity(city.isUnlocked ? 0.98 : 0.76), lineWidth: city.isUnlocked ? 2.2 : 1.3)
                }

                Annotation("", coordinate: city.centerCoordinate) {
                    CityCenterMarker(
                        cityName: city.cityName,
                        color: city.isUnlocked ? Self.awardUnlockedColor : Self.cityInteriorColor,
                        isUnlocked: city.isUnlocked
                    )
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .environment(\.colorScheme, .dark)
    }

    private var mapLegend: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                LegendItem(label: "Edge", color: Self.cityBoundaryColor, symbol: .stroke)
                LegendItem(label: "City", color: Self.cityInteriorColor, symbol: .fill)
                LegendItem(label: "Unlocked", color: Self.awardUnlockedColor, symbol: .fill)
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.cities) { city in
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
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 10)
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
    private static let cityInteriorColor = Color(red: 0.03, green: 0.72, blue: 0.82)
    private static let awardUnlockedColor = Color(red: 1.00, green: 0.72, blue: 0.12)

    private static func fillColor(for city: RegionAchievementMapCity) -> Color {
        city.isUnlocked ? awardUnlockedColor : cityInteriorColor
    }

    private static func fillOpacity(for city: RegionAchievementMapCity) -> Double {
        city.isUnlocked ? 0.38 : 0.24
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
}

private struct CityCenterMarker: View {
    let cityName: String
    let color: Color
    let isUnlocked: Bool

    var body: some View {
        VStack(spacing: 4) {
            if isUnlocked {
                Text(cityName)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.75), radius: 2, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Circle()
                .fill(color)
                .frame(width: isUnlocked ? 20 : 11, height: isUnlocked ? 20 : 11)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(isUnlocked ? 1 : 0.72), lineWidth: isUnlocked ? 3 : 1.5)
                }
                .overlay(alignment: .center) {
                    if isUnlocked {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .shadow(color: .black.opacity(0.28), radius: 2, x: 0, y: 1)
        }
        .allowsHitTesting(false)
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
