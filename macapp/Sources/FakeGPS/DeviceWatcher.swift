import Combine
import Foundation

/// Polls the runtime's `usbmux` mode to detect whether an iPhone is plugged in,
/// independently of the developer tunnel. Used by the onboarding checklist so it
/// can tell the user "iPhone detected" before anything else is set up.
@MainActor
final class DeviceWatcher: ObservableObject {
    @Published private(set) var deviceCount = 0

    var hasDevice: Bool { deviceCount > 0 }

    private let launch: () -> (executable: URL, args: [String])
    private var timer: Timer?
    private var polling = false

    init(launch: @escaping () -> (executable: URL, args: [String])) {
        self.launch = launch
        let t = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Task { await poll() }
    }

    private func poll() async {
        guard !polling else { return }
        polling = true
        defer { polling = false }

        let (exe, args) = launch()
        guard FileManager.default.isExecutableFile(atPath: exe.path) else { return }

        let count: Int? = await Task.detached {
            let proc = Process()
            proc.executableURL = exe
            proc.arguments = args
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = Pipe()
            do { try proc.run() } catch { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let devices = obj["devices"] as? [[String: Any]]
            else { return nil }
            return devices.count
        }.value

        if let count, count != deviceCount { deviceCount = count }
    }
}
