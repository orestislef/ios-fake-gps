
import CoreLocation
import Foundation

enum ChinaCoordinates {
	private static let a = 6378245.0
	private static let ee = 0.00669342162296594323

	static func gcj02ToWgs84(
		_ coordinate: CLLocationCoordinate2D
	) -> CLLocationCoordinate2D {
		let lat = coordinate.latitude
		let lon = coordinate.longitude

		guard lat.isFinite, lon.isFinite,
			(0...60).contains(lat),
			(70...140).contains(lon)
		else {
			return coordinate
		}

		var wgsLat = lat
		var wgsLon = lon

		for _ in 0..<8 {
			let projected = wgs84ToGcj02(
				CLLocationCoordinate2D(
					latitude: wgsLat,
					longitude: wgsLon
				)
			)

			wgsLat += lat - projected.latitude
			wgsLon += lon - projected.longitude
		}

		return CLLocationCoordinate2D(
			latitude: wgsLat,
			longitude: wgsLon
		)
	}

	private static func wgs84ToGcj02(
		_ coordinate: CLLocationCoordinate2D
	) -> CLLocationCoordinate2D {
		let lat = coordinate.latitude
		let lon = coordinate.longitude

		let x = lon - 105.0
		let y = lat - 35.0

		var dLat = transformLat(x, y)
		var dLon = transformLon(x, y)

		let radLat = lat * .pi / 180
		let sinLat = sin(radLat)

		let magic = 1 - ee * sinLat * sinLat
		let sqrtMagic = sqrt(magic)

		dLat = dLat * 180 / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)

		dLon = dLon * 180 / (a / sqrtMagic * cos(radLat) * .pi)

		return CLLocationCoordinate2D(
			latitude: lat + dLat,
			longitude: lon + dLon
		)
	}

	private static func transformLat(
		_ x: Double, _ y: Double
	) -> Double {
		var result =
			-100.0 + 2 * x + 3 * y
			+ 0.2 * y * y + 0.1 * x * y
			+ 0.2 * sqrt(abs(x))

		result +=
			(20 * sin(6 * x * .pi)
				+ 20 * sin(2 * x * .pi)) * 2 / 3

		result +=
			(20 * sin(y * .pi)
				+ 40 * sin(y / 3 * .pi)) * 2 / 3

		result +=
			(160 * sin(y / 12 * .pi)
				+ 320 * sin(y * .pi / 30)) * 2 / 3

		return result
	}

	private static func transformLon(
		_ x: Double, _ y: Double
	) -> Double {
		var result =
			300.0 + x + 2 * y
			+ 0.1 * x * x + 0.1 * x * y
			+ 0.1 * sqrt(abs(x))

		result +=
			(20 * sin(6 * x * .pi)
				+ 20 * sin(2 * x * .pi)) * 2 / 3

		result +=
			(20 * sin(x * .pi)
				+ 40 * sin(x / 3 * .pi)) * 2 / 3

		result +=
			(150 * sin(x / 12 * .pi)
				+ 300 * sin(x / 30 * .pi)) * 2 / 3

		return result
	}
}
