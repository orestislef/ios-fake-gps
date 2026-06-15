import Foundation

/// How the Python side (sidecar / tunnel / usbmux) is provided.
enum RuntimeKind {
    /// A standalone PyInstaller binary shipped inside FakeGPS.app. No Python
    /// install needed on the machine.
    case bundled(URL)
    /// A development setup: the venv's python running `fakegps_runtime.py`.
    case dev(python: URL, script: URL)
}

/// Resolves how to launch the runtime in its three modes: `sidecar`, `tunneld`
/// and `usbmux`. Both bundled and dev paths funnel through the same
/// `fakegps_runtime` entry point, so behaviour is identical.
@MainActor
final class AppConfig: ObservableObject {
    let runtime: RuntimeKind

    init() {
        self.runtime = Self.resolve()
    }

    private static func resolve() -> RuntimeKind {
        if let res = Bundle.main.resourceURL {
            let frozen = res.appendingPathComponent("runtime/fakegps-runtime")
            if FileManager.default.isExecutableFile(atPath: frozen.path) {
                return .bundled(frozen)
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let python = home.appendingPathComponent(".ios-fake-gps/venv/bin/python")
        let script = home.appendingPathComponent(".ios-fake-gps/fakegps_runtime.py")
        return .dev(python: python, script: script)
    }

    /// (executable, leading args) for a runtime mode. Append extra args as needed.
    func launch(_ mode: String) -> (executable: URL, args: [String]) {
        switch runtime {
        case let .bundled(bin):
            return (bin, [mode])
        case let .dev(python, script):
            return (python, [script.path, mode])
        }
    }

    var sidecarLaunch: (executable: URL, args: [String]) { launch("sidecar") }
    var usbmuxLaunch: (executable: URL, args: [String]) { launch("usbmux") }

    /// Tunnel daemon as (path, args) for the privileged osascript shell.
    var tunneldLaunch: (path: String, args: [String]) {
        let l = launch("tunneld")
        return (l.executable.path, l.args)
    }

    var isValid: Bool {
        switch runtime {
        case let .bundled(bin):
            return FileManager.default.isExecutableFile(atPath: bin.path)
        case let .dev(python, script):
            return FileManager.default.isExecutableFile(atPath: python.path)
                && FileManager.default.fileExists(atPath: script.path)
        }
    }

    var locationDescription: String {
        switch runtime {
        case let .bundled(bin): return bin.deletingLastPathComponent().path
        case let .dev(python, _): return python.deletingLastPathComponent().path
        }
    }
}
