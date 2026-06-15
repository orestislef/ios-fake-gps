import AppKit
import SwiftUI

/// Ensures the device location is reset to real GPS when the app quits, and that
/// closing the window actually quits the app (so that cleanup runs).
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate?()
    }
}

@main
struct FakeGPSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var config: AppConfig
    @StateObject private var sidecar: Sidecar
    @StateObject private var engine: SimulationEngine
    @StateObject private var tunnel: TunnelManager
    @StateObject private var devices: DeviceWatcher

    init() {
        let config = AppConfig()
        let launch = config.sidecarLaunch
        let sidecar = Sidecar(executableURL: launch.executable, argsPrefix: launch.args)
        let engine = SimulationEngine(sidecar: sidecar)
        let tunneldCmd = config.tunneldLaunch
        let tunnel = TunnelManager(tunneldCommand: { tunneldCmd })
        let usbmuxCmd = config.usbmuxLaunch
        let devices = DeviceWatcher(launch: { usbmuxCmd })

        _config = StateObject(wrappedValue: config)
        _sidecar = StateObject(wrappedValue: sidecar)
        _engine = StateObject(wrappedValue: engine)
        _tunnel = StateObject(wrappedValue: tunnel)
        _devices = StateObject(wrappedValue: devices)
    }

    var body: some Scene {
        WindowGroup("iOS Fake GPS") {
            ContentView()
                .environmentObject(config)
                .environmentObject(sidecar)
                .environmentObject(engine)
                .environmentObject(tunnel)
                .environmentObject(devices)
                .onAppear {
                    let sc = sidecar
                    appDelegate.onTerminate = {
                        MainActor.assumeIsolated { sc.shutdownBlocking() }
                    }
                }
        }
        .windowResizability(.contentSize)
    }
}
