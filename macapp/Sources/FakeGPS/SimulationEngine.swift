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
    @Published var speedKmh: Double = 50      // target ground speed

    @Published var speedVariationEnabled = false
    @Published var minSpeedKmh: Double = 35
    @Published var maxSpeedKmh: Double = 55
    @Published var accelerationKmhPerSecond: Double = 1.5

    @Published private(set) var actualSpeedKmh: Double = 50

    @Published var loop: Bool = false
    @Published var jitterMetres: Double = 0   // 0 = perfectly smooth

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

    // MARK: - Editing

    func addWaypoint(_ c: CLLocationCoordinate2D) {
        waypoints.append(Waypoint(coordinate: c))
    }

    func clearRoute() {
        stop()
        waypoints.removeAll()
        currentCoordinate = nil
        progress = 0
    }

    // MARK: - Teleport (single static location)

    func teleport(to c: CLLocationCoordinate2D) {
        guard sidecar.state.isReady else { return }
        currentCoordinate = c
        sidecar.setLocation(c.latitude, c.longitude)
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
        sidecar.setLocation(c.latitude, c.longitude)
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
