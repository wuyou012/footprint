import MapKit
import SwiftUI

enum FootprintMapStyle: String, CaseIterable, Identifiable {
    case standard
    case satellite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .satellite: "Satellite"
        }
    }

    var symbolName: String {
        switch self {
        case .standard: "map"
        case .satellite: "network"
        }
    }

    func mapStyle(
        dimension: FootprintMapDimension,
        poiVisibility: FootprintPOIVisibility
    ) -> MapStyle {
        switch self {
        case .standard:
            .standard(
                elevation: dimension.elevation,
                pointsOfInterest: poiVisibility.categories
            )
        case .satellite:
            .imagery(elevation: dimension.elevation)
        }
    }
}

enum FootprintMapDimension: String, CaseIterable, Identifiable {
    case twoD
    case threeD

    var id: String { rawValue }

    var label: String {
        switch self {
        case .twoD: "2D"
        case .threeD: "3D"
        }
    }

    var elevation: MapStyle.Elevation {
        switch self {
        case .twoD: .flat
        case .threeD: .realistic
        }
    }

    var pitch: Double {
        switch self {
        case .twoD: 0
        case .threeD: 55
        }
    }
}

enum FootprintPOIVisibility: String, CaseIterable, Identifiable {
    case shown
    case hidden

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shown: "Show"
        case .hidden: "Hide"
        }
    }

    var categories: PointOfInterestCategories {
        switch self {
        case .shown: .all
        case .hidden: .excludingAll
        }
    }
}

enum TrackTint: String, CaseIterable, Identifiable {
    case lagoon
    case ember
    case orchid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lagoon: "Lagoon"
        case .ember: "Ember"
        case .orchid: "Orchid"
        }
    }

    var appearance: TrackMapAppearance {
        switch self {
        case .lagoon:
            TrackMapAppearance(
                pathColor: Color(red: 0.00, green: 0.62, blue: 0.72),
                pointColor: Color(red: 0.14, green: 0.82, blue: 0.82),
                latestPointColor: Color(red: 0.00, green: 0.45, blue: 0.82),
                startPointColor: Color(red: 0.18, green: 0.70, blue: 0.28)
            )
        case .ember:
            TrackMapAppearance(
                pathColor: Color(red: 0.92, green: 0.33, blue: 0.10),
                pointColor: Color(red: 1.00, green: 0.66, blue: 0.21),
                latestPointColor: Color(red: 0.80, green: 0.12, blue: 0.10),
                startPointColor: Color(red: 0.17, green: 0.56, blue: 0.33)
            )
        case .orchid:
            TrackMapAppearance(
                pathColor: Color(red: 0.62, green: 0.22, blue: 0.86),
                pointColor: Color(red: 0.95, green: 0.42, blue: 0.72),
                latestPointColor: Color(red: 0.40, green: 0.19, blue: 0.78),
                startPointColor: Color(red: 0.05, green: 0.58, blue: 0.48)
            )
        }
    }
}

struct TrackMapAppearance {
    var pathColor: Color
    var pointColor: Color
    var latestPointColor: Color
    var startPointColor: Color
    var lineWidth: Double = 4
    var showsTrackPoints = true
    var maxPointMarkers = 160

    static let live = TrackTint.lagoon.appearance
    static func custom(trackColor: RGBColor) -> TrackMapAppearance {
        TrackMapAppearance(
            pathColor: trackColor.color,
            pointColor: trackColor.color,
            latestPointColor: trackColor.color,
            startPointColor: Color(red: 0.18, green: 0.70, blue: 0.28)
        )
    }

    static let history = TrackMapAppearance(
        pathColor: Color(red: 0.18, green: 0.47, blue: 0.92),
        pointColor: Color(red: 0.32, green: 0.60, blue: 0.96),
        latestPointColor: Color(red: 0.12, green: 0.30, blue: 0.78),
        startPointColor: Color(red: 0.18, green: 0.63, blue: 0.35),
        lineWidth: 3,
        showsTrackPoints: false,
        maxPointMarkers: 400
    )
}

struct TrackMapView: View {
    let points: [TrackPoint]
    var mapAnchorCoordinate: CLLocationCoordinate2D?
    var followLatest = false
    var mapStyle: FootprintMapStyle = .standard
    var mapDimension: FootprintMapDimension = .twoD
    var poiVisibility: FootprintPOIVisibility = .shown
    var mapTintColor: RGBColor = .defaultMapTint
    var mapTintStrength: Double = 0
    var appearance: TrackMapAppearance = .live

    private let segments: [MapSegment]
    private let sampledTrackPoints: [TrackMapPoint]
    private let firstPoint: TrackPoint?
    private let lastPoint: TrackPoint?
    private let trackRegion: MKCoordinateRegion?
    private let latestToken: TrackChangeToken

    @State private var position: MapCameraPosition = .region(Self.fallbackRegion)

    init(
        points: [TrackPoint],
        mapAnchorCoordinate: CLLocationCoordinate2D? = nil,
        followLatest: Bool = false,
        mapStyle: FootprintMapStyle = .standard,
        mapDimension: FootprintMapDimension = .twoD,
        poiVisibility: FootprintPOIVisibility = .shown,
        mapTintColor: RGBColor = .defaultMapTint,
        mapTintStrength: Double = 0,
        appearance: TrackMapAppearance = .live
    ) {
        self.points = points
        self.mapAnchorCoordinate = mapAnchorCoordinate
        self.followLatest = followLatest
        self.mapStyle = mapStyle
        self.mapDimension = mapDimension
        self.poiVisibility = poiVisibility
        self.mapTintColor = mapTintColor
        self.mapTintStrength = mapTintStrength
        self.appearance = appearance
        self.segments = Self.makeSegments(from: points)
        self.sampledTrackPoints = Self.makeSampledTrackPoints(
            from: points,
            followLatest: followLatest,
            maxPointMarkers: appearance.maxPointMarkers
        )
        self.firstPoint = points.first
        self.lastPoint = points.last
        self.trackRegion = Self.makeTrackRegion(from: points)
        self.latestToken = TrackChangeToken(
            count: points.count,
            lastTimestampMs: points.last?.timestampMs,
            lastLatitude: points.last?.latitude,
            lastLongitude: points.last?.longitude,
            anchorLatitude: mapAnchorCoordinate?.latitude,
            anchorLongitude: mapAnchorCoordinate?.longitude
        )
    }

    var body: some View {
        GeometryReader { proxy in
            if Self.canRenderMap(size: proxy.size) {
                mapContent
            } else {
                Color.clear
            }
        }
        .onAppear { updateCamera() }
        .onChange(of: latestToken) { _, _ in updateCamera(animated: followLatest) }
        .onChange(of: followLatest) { _, _ in updateCamera(animated: true) }
        .onChange(of: mapDimension) { _, _ in updateCamera(animated: true) }
    }

    private var mapContent: some View {
        Map(position: $position) {
            ForEach(segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(appearance.pathColor, style: StrokeStyle(lineWidth: appearance.lineWidth, lineCap: .round, lineJoin: .round))
            }
            if appearance.showsTrackPoints {
                ForEach(sampledTrackPoints) { point in
                    MapCircle(center: point.coordinate, radius: point.radiusMeters)
                        .foregroundStyle(appearance.pointColor.opacity(0.62))
                }
            }
            if points.count > 1, let first = firstPoint {
                Annotation("Start", coordinate: first.coordinate) {
                    Circle()
                        .fill(appearance.startPointColor)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 13, height: 13)
                }
            }
            if let last = lastPoint {
                Annotation("Last", coordinate: last.coordinate) {
                    Circle()
                        .fill(appearance.latestPointColor)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 17, height: 17)
                }
            }
        }
        .mapStyle(mapStyle.mapStyle(dimension: mapDimension, poiVisibility: poiVisibility))
        .overlay {
            mapTintOverlay
        }
    }

    @ViewBuilder
    private var mapTintOverlay: some View {
        if mapTintStrength > 0 {
            mapTintColor.color
                .opacity(min(0.60, max(0, mapTintStrength)))
                .blendMode(.softLight)
                .allowsHitTesting(false)
        }
    }

    private static func makeSegments(from points: [TrackPoint]) -> [MapSegment] {
        var result: [MapSegment] = []
        var indexes: [String: Int] = [:]
        for point in points {
            let key = point.segmentID.map { "segment-\($0)" } ?? "legacy"
            if let index = indexes[key] {
                result[index].coordinates.append(point.coordinate)
            } else {
                indexes[key] = result.count
                result.append(MapSegment(id: key, coordinates: [point.coordinate]))
            }
        }
        return result.filter { $0.coordinates.count >= 2 }
    }

    private static func makeSampledTrackPoints(
        from points: [TrackPoint],
        followLatest: Bool,
        maxPointMarkers: Int
    ) -> [TrackMapPoint] {
        guard points.count > 2 else { return [] }
        let safeLimit = max(1, maxPointMarkers)
        let step = max(1, (points.count + safeLimit - 1) / safeLimit)
        return points.enumerated().compactMap { index, point in
            guard index % step == 0, index != 0, index != points.count - 1 else { return nil }
            return TrackMapPoint(id: index, coordinate: point.coordinate, radiusMeters: followLatest ? 4 : 3)
        }
    }

    private static func makeTrackRegion(from points: [TrackPoint]) -> MKCoordinateRegion? {
        guard let first = points.first else { return nil }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for point in points.dropFirst() {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.01, (maxLat - minLat) * 1.4),
                longitudeDelta: max(0.01, (maxLon - minLon) * 1.4)
            )
        )
    }

    private func updateCamera(animated: Bool = false) {
        let action = {
            if followLatest, let last = lastPoint {
                position = cameraPosition(for: Self.liveRegion(centeredAt: last.coordinate))
            } else {
                fitToTrack()
            }
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.35), action)
        } else {
            action()
        }
    }

    private func fitToTrack() {
        guard let trackRegion else {
            if let mapAnchorCoordinate {
                position = cameraPosition(for: Self.anchorRegion(centeredAt: mapAnchorCoordinate))
                return
            }
            position = cameraPosition(for: Self.fallbackRegion)
            return
        }
        position = cameraPosition(for: trackRegion)
    }

    private func cameraPosition(for region: MKCoordinateRegion) -> MapCameraPosition {
        guard mapDimension == .threeD else {
            return .region(region)
        }
        return .camera(
            MapCamera(
                centerCoordinate: region.center,
                distance: Self.cameraDistance(for: region),
                pitch: mapDimension.pitch
            )
        )
    }

    private static let fallbackCenter = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    private static let fallbackRegion = MKCoordinateRegion(
        center: fallbackCenter,
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )

    private static func liveRegion(centeredAt coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
        )
    }

    private static func anchorRegion(centeredAt coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    }

    private static func cameraDistance(for region: MKCoordinateRegion) -> CLLocationDistance {
        let latitudeMeters = region.span.latitudeDelta * 111_000
        let longitudeMeters = region.span.longitudeDelta
            * 111_000
            * max(0.25, cos(region.center.latitude * .pi / 180))
        let visibleMeters = max(latitudeMeters, longitudeMeters)
        return min(80_000, max(450, visibleMeters * 2.1))
    }

    private static func canRenderMap(size: CGSize) -> Bool {
        size.width.isFinite
            && size.height.isFinite
            && size.width > 1
            && size.height > 1
    }
}

private struct MapSegment: Identifiable {
    let id: String
    var coordinates: [CLLocationCoordinate2D]
}

private struct TrackMapPoint: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    let radiusMeters: CLLocationDistance
}

private struct TrackChangeToken: Equatable {
    let count: Int
    let lastTimestampMs: Int64?
    let lastLatitude: Double?
    let lastLongitude: Double?
    let anchorLatitude: Double?
    let anchorLongitude: Double?
}
