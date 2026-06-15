import Combine
import Foundation

/// Tracks and (optionally) launches the privileged `tunneld` daemon.
///
/// `tunneld` is what creates the per-device RemoteXPC tunnel and auto-mounts the
/// Developer Disk Image. It must run as root, so we can only *start* it via an
/// authenticated `osascript` prompt; we poll its HTTP endpoint to know if it's up.
@MainActor
final class TunnelManager: ObservableObject {
    @Published private(set) var isUp = false

    private var pollTimer: Timer?
    let pythonBinDir: () -> URL // directory containing the venv's pymobiledevice3

    init(pythonBinDir: @escaping () -> URL) {
        self.pythonBinDir = pythonBinDir
        startPolling()
    }

    private func startPolling() {
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
        Task { await poll() }
    }

    private func poll() async {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:49151")!)
        req.timeoutInterval = 1.0
        let up: Bool
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            up = (resp as? HTTPURLResponse) != nil
        } catch {
            up = false
        }
        if up != isUp { isUp = up }
    }

    /// Launch tunneld with administrator privileges. Shows the macOS auth dialog.
    /// Runs detached so it keeps managing tunnels after this call returns.
    func startTunneld() {
        // Invoke via `python -m pymobiledevice3` rather than the console script:
        // it's immune to a stale shebang if the venv was relocated, and the venv
        // must live OUTSIDE ~/Documents or root (TCC) can't read it.
        let python = pythonBinDir().appendingPathComponent("python").path
        // `do shell script ... &` is reaped when the privileged session ends, so
        // detach with nohup + setsid-style disown via `&` after redirecting I/O.
        let shell = "nohup '\(python)' -m pymobiledevice3 remote tunneld "
            + "> /tmp/ios-fake-gps-tunneld.log 2>&1 &"
        let escaped = shell.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
    }
}
