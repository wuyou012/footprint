import MapKit
import SwiftUI

struct TrackMapView: View {
    let points: [TrackPoint]
    var followLatest = false

    @State private var position: MapCameraPosition = .region(Self.fallbackRegion)

    var body: some View {
        Map(position: $position) {
            ForEach(segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(.teal, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let last = points.last {
                Annotation("Last", coordinate: last.coordinate) {
                    Circle()
                        .fill(.teal)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 16, height: 16)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .onAppear { updateCamera() }
        .onChange(of: points) { _, _ in updateCamera(animated: followLatest) }
        .onChange(of: followLatest) { _, _ in updateCamera(animated: true) }
    }

    private var segments: [MapSegment] {
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

    private func updateCamera(animated: Bool = false) {
        let action = {
            if followLatest, let last = points.last {
                position = .region(Self.liveRegion(centeredAt: last.coordinate))
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
        guard !points.isEmpty else {
            position = .region(Self.fallbackRegion)
            return
        }

        let coordinates = points.map(\.coordinate)
        let minLat = coordinates.map(\.latitude).min() ?? Self.fallbackCenter.latitude
        let maxLat = coordinates.map(\.latitude).max() ?? Self.fallbackCenter.latitude
        let minLon = coordinates.map(\.longitude).min() ?? Self.fallbackCenter.longitude
        let maxLon = coordinates.map(\.longitude).max() ?? Self.fallbackCenter.longitude

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latDelta = max(0.01, (maxLat - minLat) * 1.4)
        let lonDelta = max(0.01, (maxLon - minLon) * 1.4)
        position = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        ))
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
}

private struct MapSegment: Identifiable {
    let id: String
    var coordinates: [CLLocationCoordinate2D]
}
