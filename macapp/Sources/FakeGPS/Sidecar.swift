import Combine
import Foundation

/// A device reported by the Python sidecar.
struct DeviceInfo: Identifiable, Hashable, Codable {
    var udid: String
    var name: String?
    var productType: String?
    var productVersion: String?

    var id: String { udid }
    var display: String {
        let model = productType ?? "iPhone"
        let os = productVersion.map { " · iOS \($0)" } ?? ""
        return "\(name ?? model)\(os)"
    }

    enum CodingKeys: String, CodingKey {
        case udid, name
        case productType = "product_type"
        case productVersion = "product_version"
    }
}

enum SidecarState: Equatable {
    case stopped
    case launching
    case ready(DeviceInfo)
    case failed(String)

    var isReady: Bool { if case .ready = self { return true }; return false }
}

/// Manages the lifetime of the `gpsd_helper.py` sidecar process and the
/// newline-delimited JSON protocol spoken over its stdin/stdout pipes.
@MainActor
final class Sidecar: ObservableObject {
    @Published private(set) var state: SidecarState = .stopped
    @Published private(set) var lastError: String?

    /// Path to the venv's python interpreter and the helper script.
    var pythonURL: URL
    var scriptURL: URL

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutBuffer = Data()
    private var messageID = 0

    init(pythonURL: URL, scriptURL: URL) {
        self.pythonURL = pythonURL
        self.scriptURL = scriptURL
    }

    // MARK: - Lifecycle

    func start(udid: String? = nil) {
        stop()
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            state = .failed("Python not found at \(pythonURL.path). Run the sidecar setup.")
            return
        }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            state = .failed("Sidecar script not found at \(scriptURL.path).")
            return
        }

        state = .launching
        lastError = nil

        let proc = Process()
        proc.executableURL = pythonURL
        var args = [scriptURL.path]
        if let udid { args += ["--udid", udid] }
        proc.arguments = args

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.ingest(data) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let s = String(data: data, encoding: .utf8), !s.isEmpty {
                FileHandle.standardError.write(Data(s.utf8))
            }
        }
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.handleTermination() }
        }

        do {
            try proc.run()
        } catch {
            state = .failed("Could not launch sidecar: \(error.localizedDescription)")
            return
        }
        process = proc
        stdinPipe = inPipe
    }

    func stop() {
        if let proc = process, proc.isRunning {
            send(["cmd": "quit"])
            proc.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutBuffer.removeAll()
        if case .ready = state { state = .stopped }
        if case .launching = state { state = .stopped }
    }

    private func handleTermination() {
        process = nil
        stdinPipe = nil
        if state.isReady || state == .launching {
            state = .stopped
        }
    }

    // MARK: - Commands

    func setLocation(_ lat: Double, _ lon: Double) {
        messageID += 1
        send(["cmd": "set", "lat": lat, "lon": lon, "id": messageID])
    }

    func clearLocation() {
        messageID += 1
        send(["cmd": "clear", "id": messageID])
    }

    private func send(_ obj: [String: Any]) {
        guard let pipe = stdinPipe,
              let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        var line = data
        line.append(0x0A) // newline
        pipe.fileHandleForWriting.write(line)
    }

    // MARK: - Incoming NDJSON

    private func ingest(_ data: Data) {
        stdoutBuffer.append(data)
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer[stdoutBuffer.startIndex ..< nl]
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex ... nl)
            guard !lineData.isEmpty else { continue }
            handleEvent(lineData)
        }
    }

    private func handleEvent(_ lineData: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let event = obj["event"] as? String else { return }

        switch event {
        case "ready":
            if let devObj = obj["device"],
               let devData = try? JSONSerialization.data(withJSONObject: devObj),
               let dev = try? JSONDecoder().decode(DeviceInfo.self, from: devData) {
                state = .ready(dev)
            } else {
                state = .ready(DeviceInfo(udid: "?", name: "Device", productType: nil, productVersion: nil))
            }
        case "error":
            let msg = obj["message"] as? String ?? "unknown error"
            lastError = msg
            if (obj["fatal"] as? Bool) == true {
                state = .failed(msg)
            }
        case "ok", "pong", "devices", "bye":
            break
        default:
            break
        }
    }
}
