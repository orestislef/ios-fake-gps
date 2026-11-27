import Combine
import CoreLocation
import Foundation

/// A point the user dropped on the map.
struct Waypoint: Identifiable, Hashable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D

    static func == (l: Waypoint, r: Waypoint) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum PlaybackState: Equatable {
    case idle
    case playing
    case paused
}

/// Drives simulated movement along the route at a chosen speed and pushes each
/// interpolated coordinate to the device through the `Sidecar`.
///
/// This is the part that makes us Lockito-equivalent: we own the interpolation,
/// so speed, pause, loop and GPS jitter are all under our control rather than
/// relying on the device's own GPX timing.
@MainActor
final class SimulationEngine: ObservableObject {
    @Published var waypoints: [Waypoint] = []

    var canUndo: Bool {
        !waypoints.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    private var redoStack: [Waypoint] = []

    @Published var speedKmh: Double = 50      // target ground speed

    @Published var speedVariationEnabled = false
    @Published var minSpeedKmh: Double = 35
    @Published var maxSpeedKmh: Double = 55
    @Published var accelerationKmhPerSecond: Double = 1.5

    @Published private(set) var actualSpeedKmh: Double = 50

    @Published var loop: Bool = false
    @Published var jitterMetres: Double = 0   // 0 = perfectly smooth
    @Published var chinaCoordinateCorrection = false

    @Published private(set) var playback: PlaybackState = .idle
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    @Published private(set) var progress: Double = 0 // 0...1 along the route

    private let sidecar: Sidecar
    private var timer: Timer?
    private var travelled: Double = 0          // metres along the route
    private let tick: TimeInterval = 1.0       // update cadence (s)
    private var jitterSeed: Double = 0
    private var targetSpeedKmh: Double = 50
    private var secondsUntilSpeedChange: Double = 0
    private var lastStepDate: Date?

    init(sidecar: Sidecar) {
        self.sidecar = sidecar
    }

    private func resetSpeedVariation() {
        let low = max(1, min(minSpeedKmh, maxSpeedKmh))
        let high = max(low, max(minSpeedKmh, maxSpeedKmh))

        actualSpeedKmh = speedVariationEnabled
            ? Double.random(in: low...high)
            : max(0, speedKmh)
        
        targetSpeedKmh = actualSpeedKmh
        secondsUntilSpeedChange = 0
    }

    private func updateSpeed(deltaTime: Double) -> Double {
        guard speedVariationEnabled else {
            actualSpeedKmh = max(0, speedKmh)
            return actualSpeedKmh
        }

        let low = max(1, min(minSpeedKmh, maxSpeedKmh))
        let high = max(low, max(minSpeedKmh, maxSpeedKmh))

        secondsUntilSpeedChange -= deltaTime

        if secondsUntilSpeedChange <= 0 {
            targetSpeedKmh = Double.random(in: low...high)
            secondsUntilSpeedChange = Double.random(in: 5...15)
        }

        let difference = targetSpeedKmh - actualSpeedKmh
        let maxChange = max(0, accelerationKmhPerSecond) * deltaTime

        actualSpeedKmh += min(max(difference, -maxChange), maxChange)
        actualSpeedKmh = min(high, max(low, actualSpeedKmh))

        return actualSpeedKmh
    }

    var coordinates: [CLLocationCoordinate2D] { waypoints.map(\.coordinate) }
    var totalDistance: Double { Geo.pathLength(coordinates) }

    func undo() {
        guard let previous = waypoints.popLast() else {
            return
        }

        redoStack.append(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else {
            return
        }

        waypoints.append(next)
    }

    // MARK: - Editing

    func addWaypoint(_ c: CLLocationCoordinate2D) {
        waypoints.append(Waypoint(coordinate: c))
        redoStack.removeAll()
    }

    func clearRoute() {
        stop()
        waypoints.removeAll()
        redoStack.removeAll()
        currentCoordinate = nil
        progress = 0
    }

    // MARK: - Teleport (single static location)

    private func sendLocation(_ coordinate: CLLocationCoordinate2D) {
        let output =
            chinaCoordinateCorrection
            ? ChinaCoordinates.gcj02ToWgs84(coordinate)
            : coordinate

        sidecar.setLocation(
            output.latitude,
            output.longitude
        )
    }

    func teleport(to c: CLLocationCoordinate2D) {
        guard sidecar.state.isReady else { return }

        currentCoordinate = c
        sendLocation(c)
    }

    // MARK: - Route playback

    func play() {
        guard sidecar.state.isReady else { return }
        guard coordinates.count >= 2 else {
            // A single point behaves like teleport.
            if let only = coordinates.first { teleport(to: only) }
            return
        }

        if playback == .idle {
            travelled = 0
            resetSpeedVariation()
        }

        playback = .playing
        lastStepDate = Date()
        emitCurrent(total: totalDistance)
        scheduleTimer()
    }

    func pause() {
        guard playback == .playing else { return }
        playback = .paused
        timer?.invalidate()
        timer = nil
        lastStepDate = nil
    }

    func stop() {
        playback = .idle
        travelled = 0
        progress = 0
        timer?.invalidate()
        timer = nil
        lastStepDate = nil
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: tick, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func step() {
        guard playback == .playing else { return }

        let total = totalDistance
        guard total > 0 else { stop(); return }

        let now = Date()
        let deltaTime = max(0, now.timeIntervalSince(lastStepDate ?? now))
        lastStepDate = now
        
        let currentSpeed = updateSpeed(deltaTime: deltaTime)
        let speedMps = currentSpeed / 3.6

        travelled += speedMps * deltaTime

        if travelled >= total {
            if loop {
                travelled = travelled.truncatingRemainder(dividingBy: total)
            } else {
                travelled = total
                emitCurrent(total: total)
                stop()
                return
            }
        }

        emitCurrent(total: total)
    }

    private func emitCurrent(total: Double) {
        guard var c = Geo.point(along: coordinates, at: travelled) else { return }
        if jitterMetres > 0 {
            jitterSeed += 0.37
            c = Geo.jitter(c, metres: jitterMetres, seed: jitterSeed)
        }
        currentCoordinate = c
        progress = total == 0 ? 0 : min(1, travelled / total)
        sendLocation(c)
    }

    // MARK: - Route import / export

    func exportRouteData() throws -> Data {
        let route = SavedRoute(
            points: waypoints.map {
                SavedRoutePoint(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude,
                )
            },
            settings: SavedRouteSettings(
                speedKmh: speedKmh,
                speedVariationEnabled: speedVariationEnabled,
                minSpeedKmh: minSpeedKmh,
                maxSpeedKmh: maxSpeedKmh,
                accelerationKmhPerSecond: accelerationKmhPerSecond,
                loop: loop,
                jitterMetres: jitterMetres
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]

        return try encoder.encode(route)
    }


    func importRouteData(_ data: Data) throws {
        let route = try JSONDecoder().decode(
            SavedRoute.self,
            from: data
        )

        let newPoints = try route.points.map { point -> Waypoint in
            let coordinate = CLLocationCoordinate2D(
                latitude: point.latitude,
                longitude: point.longitude
            )

            guard CLLocationCoordinate2DIsValid(coordinate) else {
                throw RouteFileError.invalidCoordinate
            }

            return Waypoint(coordinate: coordinate)
        }

        let settings = route.settings

        guard
            settings.speedKmh.isFinite,
            (1...300).contains(settings.speedKmh),

            settings.minSpeedKmh.isFinite,
            settings.maxSpeedKmh.isFinite,
            (1...300).contains(settings.minSpeedKmh),
            (1...300).contains(settings.maxSpeedKmh),
            settings.minSpeedKmh <= settings.maxSpeedKmh,

            settings.accelerationKmhPerSecond.isFinite,
            (0.2...5).contains(
                settings.accelerationKmhPerSecond
            ),

            settings.jitterMetres.isFinite,
            (0...20).contains(settings.jitterMetres)
        else {
            throw RouteFileError.invalidSettings
        }

        waypoints = newPoints

        speedKmh = settings.speedKmh
        speedVariationEnabled = settings.speedVariationEnabled
        minSpeedKmh = settings.minSpeedKmh
        maxSpeedKmh = settings.maxSpeedKmh
        accelerationKmhPerSecond =
            settings.accelerationKmhPerSecond

        loop = settings.loop
        jitterMetres = settings.jitterMetres

        resetSpeedVariation()
    }

    // MARK: - Readouts

    var estimatedDurationSeconds: Double {
        let effectiveSpeed = speedVariationEnabled
            ? (minSpeedKmh + maxSpeedKmh) / 2
            : speedKmh

        let speedMps = effectiveSpeed / 3.6
        return speedMps > 0 ? totalDistance / speedMps : 0
    }
}

struct SavedRoutePoint: Codable {
    let latitude: Double
    let longitude: Double
}

struct SavedRouteSettings: Codable {
    let speedKmh: Double
    let speedVariationEnabled: Bool
    let minSpeedKmh: Double
    let maxSpeedKmh: Double
    let accelerationKmhPerSecond: Double
    let loop: Bool
    let jitterMetres: Double
}

struct SavedRoute: Codable {
    let points: [SavedRoutePoint]
    let settings: SavedRouteSettings
}

enum RouteFileError: LocalizedError {
    case invalidCoordinate
    case invalidSettings

    var errorDescription: String? {
        switch self {
        case .invalidCoordinate:
            return "Route contains invalid coordinates"
        case .invalidSettings:
            return "Route contains invalid settings"
        }
    }
}
