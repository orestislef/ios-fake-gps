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
    /// Returns (executablePath, args) for launching the tunnel daemon.
    let tunneldCommand: () -> (path: String, args: [String])

    init(tunneldCommand: @escaping () -> (path: String, args: [String])) {
        self.tunneldCommand = tunneldCommand
        startPolling()
    }

    private func startPolling() {
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.poll() }
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
    static let logPath = "/tmp/ios-fake-gps-tunneld.log"

    func startTunneld() {
        let (path, args) = tunneldCommand()
        let quotedArgs = args.map { "'\($0)'" }.joined(separator: " ")
        // Fully detach the daemon so it survives the privileged osascript session
        // ending. `nohup` fails here ("can't detach from console" — no tty), and
        // a plain `&` child can be reaped with the session, so we use perl's
        // setsid to start a brand-new session, then exec the daemon. Output goes
        // to a log file; `&` returns control to osascript immediately.
        let inner = "/usr/bin/perl -MPOSIX -e 'setsid or exit 1; exec @ARGV' "
            + "'\(path)' \(quotedArgs)"
        let shell = "\(inner) </dev/null >\(Self.logPath) 2>&1 &"
        let escaped = shell.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
    }
}
