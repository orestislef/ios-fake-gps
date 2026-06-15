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

    init(sidecar: Sidecar) {
        self.sidecar = sidecar
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
        if playback == .idle { travelled = 0 }
        playback = .playing
        scheduleTimer()
        step() // fire immediately so motion starts without a 1s delay
    }

    func pause() {
        guard playback == .playing else { return }
        playback = .paused
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        playback = .idle
        travelled = 0
        progress = 0
        timer?.invalidate()
        timer = nil
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func step() {
        let total = totalDistance
        guard total > 0 else { stop(); return }

        let speedMps = speedKmh * 1000 / 3600
        travelled += speedMps * tick

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
        let speedMps = speedKmh * 1000 / 3600
        return speedMps > 0 ? totalDistance / speedMps : 0
    }
}
