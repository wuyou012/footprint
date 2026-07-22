import Foundation

nonisolated enum ChinaGeo {
    private static let earthRadiusMeters = 6_378_245.0
    private static let eccentricity = 0.00669342162296594323

    static func isInsideChina(_ coordinate: Coordinate) -> Bool {
        guard coordinate.longitude >= 72.004,
              coordinate.longitude <= 137.8347,
              coordinate.latitude >= 0.8293,
              coordinate.latitude <= 55.8271
        else {
            return false
        }

        return !isInsideHongKong(coordinate)
            && !isInsideMacao(coordinate)
            && !isInsideTaiwan(coordinate)
    }

    static func wgs84ToGcj02(_ coordinate: Coordinate) -> Coordinate {
        guard isInsideChina(coordinate) else { return coordinate }

        var dLat = transformLatitude(
            x: coordinate.longitude - 105.0,
            y: coordinate.latitude - 35.0
        )
        var dLng = transformLongitude(
            x: coordinate.longitude - 105.0,
            y: coordinate.latitude - 35.0
        )
        let radLat = coordinate.latitude / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - eccentricity * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((earthRadiusMeters * (1 - eccentricity)) / (magic * sqrtMagic) * .pi)
        dLng = (dLng * 180.0) / (earthRadiusMeters / sqrtMagic * cos(radLat) * .pi)

        return Coordinate(
            latitude: coordinate.latitude + dLat,
            longitude: coordinate.longitude + dLng
        )
    }

    static func gcj02ToWgs84(_ coordinate: Coordinate) -> Coordinate {
        guard isInsideChina(coordinate) else { return coordinate }

        var minLatitude = coordinate.latitude - 0.01
        var maxLatitude = coordinate.latitude + 0.01
        var minLongitude = coordinate.longitude - 0.01
        var maxLongitude = coordinate.longitude + 0.01
        var result = coordinate

        for _ in 0..<32 {
            let mid = Coordinate(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            )
            let projected = wgs84ToGcj02(mid)
            let latitudeDelta = projected.latitude - coordinate.latitude
            let longitudeDelta = projected.longitude - coordinate.longitude
            result = mid

            if abs(latitudeDelta) < 1e-9, abs(longitudeDelta) < 1e-9 {
                return mid
            }
            if latitudeDelta > 0 {
                maxLatitude = mid.latitude
            } else {
                minLatitude = mid.latitude
            }
            if longitudeDelta > 0 {
                maxLongitude = mid.longitude
            } else {
                minLongitude = mid.longitude
            }
        }

        return result
    }

    static func distanceMeters(_ lhs: Coordinate, _ rhs: Coordinate) -> Double {
        let lhsLat = lhs.latitude * .pi / 180
        let rhsLat = rhs.latitude * .pi / 180
        let deltaLat = (rhs.latitude - lhs.latitude) * .pi / 180
        let deltaLng = (rhs.longitude - lhs.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lhsLat) * cos(rhsLat) * sin(deltaLng / 2) * sin(deltaLng / 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private static func isInsideHongKong(_ coordinate: Coordinate) -> Bool {
        coordinate.latitude >= 22.13
            && coordinate.latitude <= 22.57
            && coordinate.longitude >= 113.82
            && coordinate.longitude <= 114.45
    }

    private static func isInsideMacao(_ coordinate: Coordinate) -> Bool {
        coordinate.latitude >= 22.05
            && coordinate.latitude <= 22.25
            && coordinate.longitude >= 113.52
            && coordinate.longitude <= 113.65
    }

    private static func isInsideTaiwan(_ coordinate: Coordinate) -> Bool {
        coordinate.latitude >= 21.8
            && coordinate.latitude <= 25.4
            && coordinate.longitude >= 119.3
            && coordinate.longitude <= 122.1
    }

    private static func transformLatitude(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y
            + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLongitude(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y
            + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
}

nonisolated protocol CoordinateTransform: Sendable {
    func forDisplay(_ coordinate: Coordinate) -> Coordinate
}

nonisolated struct OverseasTransform: CoordinateTransform {
    func forDisplay(_ coordinate: Coordinate) -> Coordinate {
        coordinate
    }
}

nonisolated struct ChinaDisplayTransform: CoordinateTransform {
    func forDisplay(_ coordinate: Coordinate) -> Coordinate {
        ChinaGeo.isInsideChina(coordinate)
            ? ChinaGeo.wgs84ToGcj02(coordinate)
            : coordinate
    }
}
