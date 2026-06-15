import CoreLocation
import MapKit
import SwiftUI

enum EditMode: String, CaseIterable, Identifiable {
    case teleport = "Teleport"
    case route = "Route"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var config: AppConfig
    @EnvironmentObject var sidecar: Sidecar
    @EnvironmentObject var engine: SimulationEngine
    @EnvironmentObject var tunnel: TunnelManager

    @State private var mode: EditMode = .route
    @StateObject private var mapController = MapController()
    @StateObject private var search = PlaceSearch()

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 300, idealWidth: 330, maxWidth: 420)
            mapArea
                .frame(minWidth: 480, minHeight: 480)
        }
        .frame(minWidth: 880, minHeight: 560)
    }

    private var mapArea: some View {
        MapView(
            waypoints: engine.waypoints,
            currentCoordinate: engine.currentCoordinate,
            controller: mapController,
            onTap: handleTap
        )
        .overlay(alignment: .top) { searchOverlay }
    }

    // MARK: - Search overlay

    private var searchOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search address or place…", text: $search.query)
                    .textFieldStyle(.plain)
                    .onSubmit { search.run(near: mapController.currentCenter?()) }
                    .onChange(of: search.query) { _, _ in search.run(near: mapController.currentCenter?()) }
                if search.isSearching {
                    ProgressView().controlSize(.small)
                } else if !search.query.isEmpty {
                    Button { search.clear() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            if !search.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(search.results.prefix(8).enumerated()), id: \.offset) { _, item in
                        Button { choose(item) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.displayTitle).fontWeight(.medium)
                                Text(item.displaySubtitle).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 5).padding(.horizontal, 8)
                        Divider()
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: 360)
        .padding(10)
    }

    private func choose(_ item: MKMapItem) {
        let coord = item.coordinate
        mapController.center(on: coord, meters: 1_200)
        switch mode {
        case .teleport: engine.teleport(to: coord)
        case .route: engine.addWaypoint(coord)
        }
        search.clear()
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                connectionSection
                Divider()
                modeSection
                if mode == .route { routeSection }
                Divider()
                statusFooter
            }
            .padding(16)
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device").font(.headline)

            statusRow(
                ok: tunnel.isUp,
                label: tunnel.isUp ? "Tunnel daemon running" : "Tunnel daemon not running"
            )
            if !tunnel.isUp {
                Button("Start tunnel (admin)…") { tunnel.startTunneld() }
                Text("Needs your password. Keep the iPhone plugged in with Developer Mode on.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            switch sidecar.state {
            case .stopped:
                Button("Connect") { sidecar.start() }
                    .disabled(!tunnel.isUp || !config.isValid)
            case .launching:
                HStack { ProgressView().controlSize(.small); Text("Connecting…") }
            case let .ready(dev):
                statusRow(ok: true, label: dev.display)
                Button("Disconnect") { engine.stop(); sidecar.stop() }
            case let .failed(msg):
                statusRow(ok: false, label: "Failed")
                Text(msg).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                Button("Retry") { sidecar.start() }.disabled(!tunnel.isUp)
            }

            if !config.isValid {
                Text("Sidecar not found at \(config.sidecarRoot.path)")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $mode) {
                ForEach(EditMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(mode == .teleport
                 ? "Click the map to jump the device to that point."
                 : "Click the map to add route points. Then press play.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Speed").frame(width: 54, alignment: .leading)
                Slider(value: $engine.speedKmh, in: 1 ... 300)
                Text("\(Int(engine.speedKmh)) km/h").monospacedDigit().frame(width: 70, alignment: .trailing)
            }

            HStack {
                Text("Jitter").frame(width: 54, alignment: .leading)
                Slider(value: $engine.jitterMetres, in: 0 ... 20)
                Text("\(Int(engine.jitterMetres)) m").monospacedDigit().frame(width: 70, alignment: .trailing)
            }

            Toggle("Loop route", isOn: $engine.loop)

            // Transport controls
            HStack(spacing: 10) {
                switch engine.playback {
                case .idle:
                    Button { engine.play() } label: { Label("Play", systemImage: "play.fill") }
                        .disabled(!canPlay)
                case .playing:
                    Button { engine.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                case .paused:
                    Button { engine.play() } label: { Label("Resume", systemImage: "play.fill") }
                }
                Button { engine.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .disabled(engine.playback == .idle)
                Spacer()
                Button(role: .destructive) { engine.clearRoute() } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(engine.waypoints.isEmpty)
            }

            if engine.playback != .idle {
                ProgressView(value: engine.progress)
            }

            routeStats
        }
    }

    private var routeStats: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(engine.waypoints.count) points · \(formatDistance(engine.totalDistance))")
            if engine.totalDistance > 0 {
                Text("ETA \(formatDuration(engine.estimatedDurationSeconds)) at \(Int(engine.speedKmh)) km/h")
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let c = engine.currentCoordinate {
                Text(String(format: "Now: %.6f, %.6f", c.latitude, c.longitude))
                    .font(.caption.monospaced())
            }
            if let err = sidecar.lastError, !sidecar.state.isFailed {
                Text(err).font(.caption).foregroundStyle(.orange)
            }
            if sidecar.state.isReady {
                Button("Reset device location") { sidecar.clearLocation(); engine.stop() }
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Helpers

    private var canPlay: Bool {
        sidecar.state.isReady && engine.waypoints.count >= 1
    }

    private func handleTap(_ c: CLLocationCoordinate2D) {
        switch mode {
        case .teleport:
            engine.teleport(to: c)
        case .route:
            engine.addWaypoint(c)
        }
    }

    private func statusRow(ok: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            Text(label).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formatDistance(_ m: Double) -> String {
        m >= 1000 ? String(format: "%.2f km", m / 1000) : String(format: "%.0f m", m)
    }

    private func formatDuration(_ s: Double) -> String {
        let total = Int(s.rounded())
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }
}

private extension SidecarState {
    var isFailed: Bool { if case .failed = self { return true }; return false }
}
