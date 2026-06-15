import Foundation

/// Resolves where the Python sidecar lives. Defaults assume the standard repo
/// layout (…/ios-fake-gps/sidecar) but are user-overridable and persisted.
@MainActor
final class AppConfig: ObservableObject {
    @Published var sidecarRoot: URL { didSet { persist() } }

    private static let key = "sidecarRoot"

    init() {
        if let saved = UserDefaults.standard.url(forKey: Self.key) {
            sidecarRoot = saved
        } else {
            sidecarRoot = Self.guessRoot()
        }
    }

    var pythonURL: URL { sidecarRoot.appendingPathComponent("venv/bin/python") }
    var scriptURL: URL { sidecarRoot.appendingPathComponent("gpsd_helper.py") }

    var isValid: Bool {
        FileManager.default.isExecutableFile(atPath: pythonURL.path)
            && FileManager.default.fileExists(atPath: scriptURL.path)
    }

    private func persist() {
        UserDefaults.standard.set(sidecarRoot, forKey: Self.key)
    }

    /// Best-effort guess for the runtime root (venv + gpsd_helper.py).
    ///
    /// We default to a dot-folder in $HOME — NOT ~/Documents — because the
    /// privileged `tunneld` daemon runs as root, and macOS TCC blocks root from
    /// reading Documents/Desktop/Downloads. A home dot-folder is root-readable.
    private static func guessRoot() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let runtime = home.appendingPathComponent(".ios-fake-gps")
        if FileManager.default.fileExists(atPath: runtime.path) { return runtime }
        // Legacy fallback (works for the GUI sidecar, but tunneld won't from here).
        let docs = home.appendingPathComponent("Documents/ios-fake-gps/sidecar")
        if FileManager.default.fileExists(atPath: docs.path) { return docs }
        return runtime
    }
}
