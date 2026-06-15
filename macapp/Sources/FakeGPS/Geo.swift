import CoreLocation
import Foundation

/// Geodesy helpers for interpolating motion along a multi-point route.
///
/// Distances use the haversine formula; intermediate points are interpolated
/// linearly in lat/lon, which is accurate enough at the per-tick granularity we
/// move (tens of metres between updates).
enum Geo {
    static let earthRadius = 6_371_000.0 // metres

    static func radians(_ deg: Double) -> Double { deg * .pi / 180 }
    static func degrees(_ rad: Double) -> Double { rad * 180 / .pi }

    /// Great-circle distance between two coordinates, in metres.
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dLat = radians(b.latitude - a.latitude)
        let dLon = radians(b.longitude - a.longitude)
        let lat1 = radians(a.latitude)
        let lat2 = radians(b.latitude)
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b`, in degrees (0 = north, clockwise).
    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = radians(a.latitude)
        let lat2 = radians(b.latitude)
        let dLon = radians(b.longitude - a.longitude)
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (degrees(atan2(y, x)) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Point a fraction `t` (0...1) of the way from `a` to `b`.
    static func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ t: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    /// Total length of a polyline in metres.
    static func pathLength(_ points: [CLLocationCoordinate2D]) -> Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for i in 0 ..< (points.count - 1) {
            total += distance(points[i], points[i + 1])
        }
        return total
    }

    /// Coordinate at arc-length `s` metres along the polyline (clamped to its ends).
    static func point(along points: [CLLocationCoordinate2D], at s: Double) -> CLLocationCoordinate2D? {
        guard let first = points.first else { return nil }
        guard points.count > 1 else { return first }
        if s <= 0 { return first }
        var remaining = s
        for i in 0 ..< (points.count - 1) {
            let segLen = distance(points[i], points[i + 1])
            if remaining <= segLen || i == points.count - 2 {
                let t = segLen == 0 ? 0 : min(1, remaining / segLen)
                return interpolate(points[i], points[i + 1], t)
            }
            remaining -= segLen
        }
        return points.last
    }

    /// Apply a small random horizontal jitter (metres) to mimic real GPS noise.
    static func jitter(_ c: CLLocationCoordinate2D, metres: Double, seed: Double) -> CLLocationCoordinate2D {
        guard metres > 0 else { return c }
        // Deterministic-ish offset derived from seed so we don't import RNG state.
        let angle = (seed.truncatingRemainder(dividingBy: 1)) * 2 * .pi
        let r = metres * (0.5 + 0.5 * abs(sin(seed * 12.9898)))
        let dLat = (r * cos(angle)) / earthRadius
        let dLon = (r * sin(angle)) / (earthRadius * cos(radians(c.latitude)))
        return CLLocationCoordinate2D(
            latitude: c.latitude + degrees(dLat),
            longitude: c.longitude + degrees(dLon)
        )
    }
}
