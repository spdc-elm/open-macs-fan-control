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

struct MenuBarExtraLabel: View {
    let snapshot: TelemetrySnapshot

    var body: some View {
        Text(
            "CPU \(formatTemperature(snapshot.cpuAverageCelsius))  GPU \(formatTemperature(snapshot.gpuAverageCelsius))  FAN \(formatFanSummary(snapshot.fanSummary))"
        )
        .monospacedDigit()
    }

    private func formatTemperature(_ value: TelemetryValue<Double>) -> String {
        guard let temperature = value.value else {
            return "--"
        }

        return "\(Int(temperature.rounded()))°"
    }

    private func formatFanSummary(_ summary: FanTelemetrySummary) -> String {
        guard let averageCurrentRPM = summary.averageCurrentRPM else {
            return "--"
        }

        return "\(averageCurrentRPM)"
    }
}

struct MenuBarPanel: View {
    @ObservedObject var store: MenuBarTelemetryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                detailRow(title: "CPU average", value: formatTemperature(store.snapshot.cpuAverageCelsius))
                detailRow(title: "GPU average", value: formatTemperature(store.snapshot.gpuAverageCelsius))
                detailRow(title: "Fan summary", value: formatFanSummary(store.snapshot.fanSummary))
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
                }

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(minWidth: 340)
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
        if store.snapshot.hasStaleSignals {
            return "Latest refresh attempt: \(refreshedAt). Some values are stale from the last successful sample."
        }
        if store.snapshot.hasUnavailableSignals {
            return "Latest refresh attempt: \(refreshedAt). Some values are unavailable on this machine."
        }
        return "Latest refresh attempt: \(refreshedAt)."
    }
}
