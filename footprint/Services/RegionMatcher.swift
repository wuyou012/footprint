import Foundation

nonisolated struct RegionMatch: Hashable, Sendable {
    let region: Region
    let polygonIndex: Int
}

nonisolated struct RegionMatcher: Sendable {
    enum MatchError: Error {
        case missingGeometry(String)
    }

    enum EdgePolicy: Sendable {
        case inside
        case outside
    }

    private struct Entry: Sendable {
        let region: Region
        let polygons: [RegionPolygon]
    }

    private let entries: [Entry]
    private let bboxPadding: Double
    private let edgePolicy: EdgePolicy

    init(
        regions: [Region],
        geometryByRegionId: [String: [RegionPolygon]],
        bboxPadding: Double = 0.0005,
        edgePolicy: EdgePolicy = .inside
    ) throws {
        self.entries = try regions
            .sorted {
                if $0.level.specificity != $1.level.specificity {
                    return $0.level.specificity > $1.level.specificity
                }
                return $0.regionId < $1.regionId
            }
            .map { region in
                guard let polygons = geometryByRegionId[region.regionId], !polygons.isEmpty else {
                    throw MatchError.missingGeometry(region.regionId)
                }
                return Entry(region: region, polygons: polygons)
            }
        self.bboxPadding = bboxPadding
        self.edgePolicy = edgePolicy
    }

    init(
        provider: RegionDataProvider,
        bboxPadding: Double = 0.0005,
        edgePolicy: EdgePolicy = .inside
    ) throws {
        let regions = try provider.regions()
        var geometryByRegionId: [String: [RegionPolygon]] = [:]
        for region in regions {
            geometryByRegionId[region.regionId] = try provider.geometry(for: region.regionId)
        }
        try self.init(
            regions: regions,
            geometryByRegionId: geometryByRegionId,
            bboxPadding: bboxPadding,
            edgePolicy: edgePolicy
        )
    }

    func match(_ point: Coordinate) -> RegionMatch? {
        for entry in entries where entry.region.bbox.contains(point, padding: bboxPadding) {
            for (index, polygon) in entry.polygons.enumerated()
                where polygon.bbox.contains(point, padding: bboxPadding)
                    && contains(point, in: polygon)
            {
                return RegionMatch(region: entry.region, polygonIndex: index)
            }
        }
        return nil
    }

    func matches(_ point: Coordinate) -> [RegionMatch] {
        entries.flatMap { entry in
            guard entry.region.bbox.contains(point, padding: bboxPadding) else {
                return [] as [RegionMatch]
            }
            return entry.polygons.enumerated().compactMap { index, polygon in
                guard polygon.bbox.contains(point, padding: bboxPadding),
                      contains(point, in: polygon)
                else { return nil }
                return RegionMatch(region: entry.region, polygonIndex: index)
            }
        }
    }

    private func contains(_ point: Coordinate, in polygon: RegionPolygon) -> Bool {
        guard contains(point, in: polygon.exterior) else { return false }
        return !polygon.holes.contains { contains(point, in: $0) }
    }

    private func contains(_ point: Coordinate, in ring: RegionRing) -> Bool {
        let coordinates = ring.closedCoordinates
        guard coordinates.count >= 4 else { return false }

        var isInside = false
        for index in 0..<(coordinates.count - 1) {
            let a = coordinates[index]
            let b = coordinates[index + 1]

            if isPoint(point, onSegmentFrom: a, to: b) {
                return edgePolicy == .inside
            }

            let crossesLatitude = (a.latitude > point.latitude) != (b.latitude > point.latitude)
            guard crossesLatitude else { continue }

            let longitudeAtLatitude = (b.longitude - a.longitude)
                * (point.latitude - a.latitude)
                / (b.latitude - a.latitude)
                + a.longitude
            if point.longitude < longitudeAtLatitude {
                isInside.toggle()
            }
        }

        return isInside
    }

    private func isPoint(_ point: Coordinate, onSegmentFrom a: Coordinate, to b: Coordinate) -> Bool {
        let cross = (point.latitude - a.latitude) * (b.longitude - a.longitude)
            - (point.longitude - a.longitude) * (b.latitude - a.latitude)
        guard abs(cross) <= 1e-12 else { return false }

        return point.latitude >= min(a.latitude, b.latitude) - 1e-12
            && point.latitude <= max(a.latitude, b.latitude) + 1e-12
            && point.longitude >= min(a.longitude, b.longitude) - 1e-12
            && point.longitude <= max(a.longitude, b.longitude) + 1e-12
    }
}
