import AppKit
import FanControlRuntime
import Foundation
import SwiftUI

@MainActor
final class MenuBarTelemetryStore: ObservableObject {
    @Published private(set) var snapshot: TelemetrySnapshot

    private let reader: TelemetryReader
    private let refreshInterval: TimeInterval
    private var timer: Timer?

    init(
        reader: TelemetryReader = TelemetryReader(),
        refreshInterval: TimeInterval = 2
    ) {
        self.reader = reader
        self.refreshInterval = refreshInterval
        self.snapshot = .unavailable(refreshedAt: Date())
        refresh()
        startTimer()
    }

    func refresh() {
        snapshot = reader.refresh(previousSnapshot: snapshot).snapshot
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
}

@MainActor
final class MenuBarControllerStore: ObservableObject {
    @Published private(set) var status = AutomaticControlStatusSnapshot.idle()
    @Published private(set) var errorMessage: String?
    @Published private(set) var activeConfig: AutomaticControlConfig?

    private let refreshInterval: TimeInterval
    private let launcher: AutomaticControlControllerLauncher
    private var timer: Timer?
    private let lastConfigKey = "menu-bar.last-controller-config"
    private var cachedConfigPath: String?

    init(
        refreshInterval: TimeInterval = 2,
        launcher: AutomaticControlControllerLauncher = AutomaticControlControllerLauncher(currentExecutablePath: CommandLine.arguments[0])
    ) {
        self.refreshInterval = refreshInterval
        self.launcher = launcher
        refresh()
        startTimer()
    }

    func refresh() {
        do {
            let client = try AutomaticControlControllerClient.connect()
            defer { try? client.close() }
            let status = try client.status()
            self.status = status
            self.errorMessage = nil
            if let configPath = status.activeConfigPath {
                UserDefaults.standard.set(configPath, forKey: lastConfigKey)
            }
            refreshActiveConfig()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func refreshActiveConfig() {
        guard let configPath = status.activeConfigPath, status.phase == .running else {
            activeConfig = nil
            cachedConfigPath = nil
            return
        }

        if configPath == cachedConfigPath, activeConfig != nil {
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            activeConfig = try JSONDecoder().decode(AutomaticControlConfig.self, from: data)
            cachedConfigPath = configPath
        } catch {
            activeConfig = nil
            cachedConfigPath = nil
        }
    }

    func stopController() {
        runControlAction {
            let client = try AutomaticControlControllerClient.connect()
            defer { try? client.close() }
            self.status = try client.stop()
        }
    }

    func reloadActiveConfig() {
        guard let configPath = status.activeConfigPath else {
            errorMessage = "No active controller config to reload."
            return
        }

        cachedConfigPath = nil
        activeConfig = nil

        runControlAction {
            let client = try AutomaticControlControllerClient.connect()
            defer { try? client.close() }
            self.status = try client.reload(configPath: configPath)
        }
    }

    func startLastKnownConfig() {
        guard let configPath = UserDefaults.standard.string(forKey: lastConfigKey), !configPath.isEmpty else {
            errorMessage = "Start automatic control from the CLI once so the menu bar can remember the config path."
            return
        }

        runControlAction {
            try launcher.ensureRunning()
            let client = try AutomaticControlControllerClient.connect()
            defer { try? client.close() }
            self.status = try client.start(configPath: configPath)
        }
    }

    private func runControlAction(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
            if let configPath = status.activeConfigPath {
                UserDefaults.standard.set(configPath, forKey: lastConfigKey)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
}

struct MenuBarPanel: View {
    @ObservedObject var store: MenuBarTelemetryStore
    @ObservedObject var controllerStore: MenuBarControllerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                detailRow(title: "CPU average", value: formatTemperature(store.snapshot.cpuAverageCelsius))
                detailRow(title: "GPU average", value: formatTemperature(store.snapshot.gpuAverageCelsius))
                detailRow(title: "Memory average", value: formatTemperature(store.snapshot.memoryAverageCelsius))
                detailRow(title: "Fan summary", value: formatFanSummary(store.snapshot.fanSummary))
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                detailRow(title: "Automatic control", value: controllerStore.status.phase.rawValue)
                detailRow(title: "Controller config", value: controllerStore.status.activeConfigPath ?? "None")
                detailRow(title: "Writer connectivity", value: controllerStore.status.writerConnected ? "Connected" : "Unavailable")

                if let errorMessage = controllerStore.errorMessage ?? controllerStore.status.lastError {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if controllerStore.status.phase == .running, let config = controllerStore.activeConfig {
                Divider()
                controlRulesSection(config: config)
            }

            if !store.snapshot.fanSummary.fans.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Fans")
                        .font(.headline)

                    ForEach(store.snapshot.fanSummary.fans, id: \.index) { fan in
                        Text(
                            "Fan \(fan.index): current=\(fan.currentRPM)rpm min=\(fan.minimumRPM)rpm max=\(fan.maximumRPM)rpm"
                        )
                        .font(.caption.monospaced())
                    }
                }
            }

            Divider()

            Text(refreshContext)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Refresh now") {
                    store.refresh()
                    controllerStore.refresh()
                }

                Spacer()

                if controllerStore.status.activeConfigPath != nil {
                    Button("Reload control") {
                        controllerStore.reloadActiveConfig()
                    }
                }

                if controllerStore.status.phase == .running || controllerStore.status.phase == .starting || controllerStore.status.phase == .failed {
                    Button("Stop control") {
                        controllerStore.stopController()
                    }
                } else {
                    Button("Start last config") {
                        controllerStore.startLastKnownConfig()
                    }
                }

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(minWidth: 460)
    }

    private func controlRulesSection(config: AutomaticControlConfig) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Control rules")
                .font(.headline)

            let fans = config.fans
            domainRuleRows(label: "CPU", domain: config.cpuDomain, fans: fans)
            domainRuleRows(label: "GPU", domain: config.gpuDomain, fans: fans)
            if let memoryDomain = config.memoryDomain {
                domainRuleRows(label: "Mem", domain: memoryDomain, fans: fans)
            }
        }
    }

    private func domainRuleRows(label: String, domain: ThermalDomainConfig, fans: [FanPolicyConfig]) -> some View {
        let startTemp = String(format: "%.0f", domain.startTemperatureCelsius)
        let maxTemp = String(format: "%.0f", domain.maxTemperatureCelsius)

        return Group {
            if fans.count <= 1 {
                let fan = fans.first
                let rpmRange = fan.map { "\($0.minimumRPM)–\($0.maximumRPM) rpm" } ?? ""
                Text("\(label)  \(domain.sensor)  \(startTemp)–\(maxTemp) °C → \(rpmRange)")
                    .font(.caption.monospaced())
            } else {
                ForEach(Array(fans.enumerated()), id: \.offset) { _, fan in
                    Text("\(label)  \(domain.sensor)  \(startTemp)–\(maxTemp) °C → Fan \(fan.fanIndex): \(fan.minimumRPM)–\(fan.maximumRPM) rpm")
                        .font(.caption.monospaced())
                }
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(value)
                .font(.body.monospacedDigit())
        }
    }

    private func formatTemperature(_ value: TelemetryValue<Double>) -> String {
        switch value.state {
        case .live:
            guard let temperature = value.value else {
                return "Unavailable"
            }
            return "\(String(format: "%.1f", temperature)) °C"
        case .stale:
            guard let temperature = value.value else {
                return "Stale"
            }
            return "\(String(format: "%.1f", temperature)) °C (stale)"
        case .unavailable:
            return "Unavailable on this machine"
        }
    }

    private func formatFanSummary(_ summary: FanTelemetrySummary) -> String {
        switch summary.state {
        case .live:
            return fanLiveSummary(summary)
        case .stale:
            return fanLiveSummary(summary) + " (stale)"
        case .unavailable:
            return "Unavailable on this machine"
        }
    }

    private func fanLiveSummary(_ summary: FanTelemetrySummary) -> String {
        guard let average = summary.averageCurrentRPM else {
            return "Unavailable"
        }

        let range: String
        if let minimum = summary.minimumCurrentRPM, let maximum = summary.maximumCurrentRPM {
            range = "avg \(average)rpm (\(minimum)-\(maximum)rpm)"
        } else {
            range = "avg \(average)rpm"
        }

        return range
    }

    private var refreshContext: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none

        let refreshedAt = formatter.string(from: store.snapshot.refreshedAt)
        let controllerPhase = controllerStore.status.phase.rawValue
        if store.snapshot.hasStaleSignals {
            return "Latest refresh attempt: \(refreshedAt). Controller phase: \(controllerPhase). Some values are stale from the last successful sample."
        }
        if store.snapshot.hasUnavailableSignals {
            return "Latest refresh attempt: \(refreshedAt). Controller phase: \(controllerPhase). Some values are unavailable on this machine."
        }
        return "Latest refresh attempt: \(refreshedAt). Controller phase: \(controllerPhase)."
    }
}
