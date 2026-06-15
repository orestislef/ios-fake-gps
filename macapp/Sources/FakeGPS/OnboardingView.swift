import SwiftUI

/// A guided checklist shown until the app is connected to a device. It detects
/// each prerequisite live (iPhone plugged in, tunnel running) and offers the
/// action for the current step — so a new user never has to read the docs.
///
/// The Python engine is bundled inside the app, so there is nothing to download;
/// the only steps are the ones macOS/Apple require a human to do.
struct OnboardingView: View {
    @EnvironmentObject var config: AppConfig
    @EnvironmentObject var sidecar: Sidecar
    @EnvironmentObject var tunnel: TunnelManager
    @EnvironmentObject var devices: DeviceWatcher

    private var engineReady: Bool { config.isValid }
    private var deviceReady: Bool { devices.hasDevice }
    private var tunnelReady: Bool { tunnel.isUp }
    private var canConnect: Bool { engineReady && tunnelReady }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                step(
                    n: 1, done: engineReady,
                    title: "Engine ready",
                    detail: engineReady
                        ? "Everything needed is bundled inside the app."
                        : "Runtime missing at \(config.locationDescription)."
                )
                step(
                    n: 2, done: deviceReady,
                    title: deviceReady ? "iPhone detected" : "Connect your iPhone",
                    detail: deviceReady
                        ? "Found a connected device."
                        : "Plug it in with a USB cable and tap Trust. Turn on Developer Mode in Settings ▸ Privacy & Security ▸ Developer Mode."
                ) {
                    if !deviceReady {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for a device…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                step(
                    n: 3, done: tunnelReady,
                    title: "Start the secure tunnel",
                    detail: tunnelReady
                        ? "Tunnel daemon is running."
                        : "Opens a developer tunnel to the device. Asks for your password once."
                ) {
                    if !tunnelReady {
                        Button("Start tunnel (admin)…") { tunnel.startTunneld() }
                            .disabled(!engineReady)
                    }
                }
                step(
                    n: 4, done: false, isFinal: true,
                    title: "Connect",
                    detail: "Link the app to your device and start spoofing."
                ) {
                    connectControl
                }
            }
            .padding(20)
        }
        .frame(width: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .shadow(radius: 30)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill.viewfinder")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set up iOS Fake GPS").font(.title3.bold())
                Text("A few quick steps and you're ready.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private var connectControl: some View {
        switch sidecar.state {
        case .launching:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Connecting…") }
        case let .failed(msg):
            VStack(alignment: .leading, spacing: 6) {
                Text(msg).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { sidecar.start() }.disabled(!canConnect)
            }
        default:
            Button("Connect") { sidecar.start() }
                .buttonStyle(.borderedProminent)
                .disabled(!canConnect)
        }
    }

    @ViewBuilder
    private func step(
        n: Int, done: Bool, isFinal: Bool = false,
        title: String, detail: String,
        @ViewBuilder action: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.secondary.opacity(0.25))
                    .frame(width: 26, height: 26)
                if done {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                } else {
                    Text("\(n)").font(.caption.bold()).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
            Spacer(minLength: 0)
        }
    }
}
