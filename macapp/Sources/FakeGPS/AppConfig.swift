import Foundation

/// How the Python side (sidecar + tunnel daemon) is provided.
enum RuntimeKind {
    /// A standalone PyInstaller binary shipped inside FakeGPS.app. No Python
    /// install needed on the machine.
    case bundled(URL)
    /// A development setup: the venv's python running the source scripts.
    case dev(python: URL, script: URL)
}

/// Resolves how to launch the sidecar and the tunnel daemon.
///
/// When running as a packaged app (FakeGPS.app), it uses the frozen
/// `fakegps-runtime` binary in `Contents/Resources/runtime`. When running via
/// `swift run` during development, it falls back to the venv in `~/.ios-fake-gps`.
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
        let venvPython = home.appendingPathComponent(".ios-fake-gps/venv/bin/python")
        let script = home.appendingPathComponent(".ios-fake-gps/gpsd_helper.py")
        return .dev(python: venvPython, script: script)
    }

    // MARK: - Sidecar launch

    /// (executable, leading args) for running the sidecar. Append e.g. `--udid X`.
    var sidecarLaunch: (executable: URL, args: [String]) {
        switch runtime {
        case let .bundled(bin):
            return (bin, ["sidecar"])
        case let .dev(python, script):
            return (python, [script.path])
        }
    }

    // MARK: - Tunnel daemon launch (used by an admin osascript shell)

    /// (executablePath, args) for `… remote tunneld`.
    var tunneldLaunch: (path: String, args: [String]) {
        switch runtime {
        case let .bundled(bin):
            return (bin.path, ["tunneld"])
        case let .dev(python, _):
            return (python.path, ["-m", "pymobiledevice3", "remote", "tunneld"])
        }
    }

    // MARK: - Validity

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
