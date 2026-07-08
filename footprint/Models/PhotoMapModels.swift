import CoreLocation
import Foundation

struct PhotoMapPoint: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var latitude: Double
    var longitude: Double
    var importedAtMs: Int64

    init(
        id: String = UUID().uuidString,
        latitude: Double,
        longitude: Double,
        importedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.importedAtMs = importedAtMs
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum PhotoLibraryImportScope: String, CaseIterable, Identifiable, Sendable {
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All photos"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "photo.stack"
        }
    }
}

struct PhotoAlbumSummary: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let assetCount: Int
}

enum PhotoMarkerRenderMode: String, CaseIterable, Identifiable, Sendable {
    case mapDot
    case fixedMarker

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mapDot: "Map dots"
        case .fixedMarker: "Fixed markers"
        }
    }

    var symbolName: String {
        switch self {
        case .mapDot: "circle.grid.cross"
        case .fixedMarker: "mappin.circle"
        }
    }
}

enum PhotoMarkerShape: String, CaseIterable, Identifiable, Sendable {
    case circle
    case square
    case diamond

    var id: String { rawValue }

    var label: String {
        switch self {
        case .circle: "Circle"
        case .square: "Square"
        case .diamond: "Diamond"
        }
    }

    var symbolName: String {
        switch self {
        case .circle: "circle.fill"
        case .square: "square.fill"
        case .diamond: "diamond.fill"
        }
    }
}
