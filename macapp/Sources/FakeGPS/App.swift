import SwiftUI

@main
struct FakeGPSApp: App {
    @StateObject private var config: AppConfig
    @StateObject private var sidecar: Sidecar
    @StateObject private var engine: SimulationEngine
    @StateObject private var tunnel: TunnelManager

    init() {
        let config = AppConfig()
        let sidecar = Sidecar(pythonURL: config.pythonURL, scriptURL: config.scriptURL)
        let engine = SimulationEngine(sidecar: sidecar)
        let binDir = config.pythonURL.deletingLastPathComponent()
        let tunnel = TunnelManager(pythonBinDir: { binDir })

        _config = StateObject(wrappedValue: config)
        _sidecar = StateObject(wrappedValue: sidecar)
        _engine = StateObject(wrappedValue: engine)
        _tunnel = StateObject(wrappedValue: tunnel)
    }

    var body: some Scene {
        WindowGroup("iOS Fake GPS") {
            ContentView()
                .environmentObject(config)
                .environmentObject(sidecar)
                .environmentObject(engine)
                .environmentObject(tunnel)
        }
        .windowResizability(.contentSize)
    }
}
