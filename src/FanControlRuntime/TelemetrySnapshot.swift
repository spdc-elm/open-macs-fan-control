import Foundation

package enum TelemetrySignalState: String {
    case live
    case unavailable
    case stale
}

package struct TelemetryValue<Value> {
    package let value: Value?
    package let state: TelemetrySignalState
    package let lastUpdatedAt: Date?

    package static func live(_ value: Value, at date: Date) -> TelemetryValue<Value> {
        TelemetryValue(value: value, state: .live, lastUpdatedAt: date)
    }

    package static func unavailable() -> TelemetryValue<Value> {
        TelemetryValue(value: nil, state: .unavailable, lastUpdatedAt: nil)
    }

    package func stale() -> TelemetryValue<Value> {
        TelemetryValue(value: value, state: .stale, lastUpdatedAt: lastUpdatedAt)
    }
}

package struct FanTelemetrySummary {
    package let fans: [FanReading]
    package let averageCurrentRPM: Int?
    package let minimumCurrentRPM: Int?
    package let maximumCurrentRPM: Int?
    package let state: TelemetrySignalState
    package let lastUpdatedAt: Date?

    package static func live(fans: [FanReading], at date: Date) -> FanTelemetrySummary {
        let currentRPMs = fans.map(\.currentRPM)
        let average = currentRPMs.isEmpty ? nil : Int((Double(currentRPMs.reduce(0, +)) / Double(currentRPMs.count)).rounded())

        return FanTelemetrySummary(
            fans: fans,
            averageCurrentRPM: average,
            minimumCurrentRPM: currentRPMs.min(),
            maximumCurrentRPM: currentRPMs.max(),
            state: .live,
            lastUpdatedAt: date
        )
    }

    package static func unavailable() -> FanTelemetrySummary {
        FanTelemetrySummary(
            fans: [],
            averageCurrentRPM: nil,
            minimumCurrentRPM: nil,
            maximumCurrentRPM: nil,
            state: .unavailable,
            lastUpdatedAt: nil
        )
    }

    package func stale() -> FanTelemetrySummary {
        FanTelemetrySummary(
            fans: fans,
            averageCurrentRPM: averageCurrentRPM,
            minimumCurrentRPM: minimumCurrentRPM,
            maximumCurrentRPM: maximumCurrentRPM,
            state: .stale,
            lastUpdatedAt: lastUpdatedAt
        )
    }
}

package struct TelemetrySnapshot {
    package let refreshedAt: Date
    package let cpuAverageCelsius: TelemetryValue<Double>
    package let gpuAverageCelsius: TelemetryValue<Double>
    package let memoryAverageCelsius: TelemetryValue<Double>
    package let fanSummary: FanTelemetrySummary

    package var hasStaleSignals: Bool {
        [cpuAverageCelsius.state, gpuAverageCelsius.state, memoryAverageCelsius.state, fanSummary.state].contains(.stale)
    }

    package var hasUnavailableSignals: Bool {
        [cpuAverageCelsius.state, gpuAverageCelsius.state, memoryAverageCelsius.state, fanSummary.state].contains(.unavailable)
    }

    package static func unavailable(refreshedAt: Date) -> TelemetrySnapshot {
        TelemetrySnapshot(
            refreshedAt: refreshedAt,
            cpuAverageCelsius: .unavailable(),
            gpuAverageCelsius: .unavailable(),
            memoryAverageCelsius: .unavailable(),
            fanSummary: .unavailable()
        )
    }
}

package struct TelemetryCapture {
    package let temperatures: [UnifiedTemperatureReading]
    package let fans: [FanReading]
    package let snapshot: TelemetrySnapshot
}

package struct TelemetrySnapshotBuilder {
    package init() {}

    package func build(
        refreshedAt: Date,
        temperatures: [UnifiedTemperatureReading],
        fans: [FanReading],
        previousSnapshot: TelemetrySnapshot? = nil
    ) -> TelemetrySnapshot {
        TelemetrySnapshot(
            refreshedAt: refreshedAt,
            cpuAverageCelsius: resolveTemperature(
                rawName: "cpu_core_average",
                temperatures: temperatures,
                refreshedAt: refreshedAt,
                previous: previousSnapshot?.cpuAverageCelsius
            ),
            gpuAverageCelsius: resolveTemperature(
                rawName: "gpu_cluster_average",
                temperatures: temperatures,
                refreshedAt: refreshedAt,
                previous: previousSnapshot?.gpuAverageCelsius
            ),
            memoryAverageCelsius: resolveTemperature(
                rawName: "memory_average",
                temperatures: temperatures,
                refreshedAt: refreshedAt,
                previous: previousSnapshot?.memoryAverageCelsius
            ),
            fanSummary: resolveFans(
                fans: fans,
                refreshedAt: refreshedAt,
                previous: previousSnapshot?.fanSummary
            )
        )
    }

    private func resolveTemperature(
        rawName: String,
        temperatures: [UnifiedTemperatureReading],
        refreshedAt: Date,
        previous: TelemetryValue<Double>?
    ) -> TelemetryValue<Double> {
        if let value = temperatures.first(where: { $0.rawName == rawName })?.valueCelsius {
            return .live(value, at: refreshedAt)
        }

        if let previous, previous.value != nil {
            return previous.stale()
        }

        return .unavailable()
    }

    private func resolveFans(
        fans: [FanReading],
        refreshedAt: Date,
        previous: FanTelemetrySummary?
    ) -> FanTelemetrySummary {
        if !fans.isEmpty {
            return .live(fans: fans, at: refreshedAt)
        }

        if let previous, previous.averageCurrentRPM != nil || !previous.fans.isEmpty {
            return previous.stale()
        }

        return .unavailable()
    }
}

package final class TelemetryReader {
    private let inventory: TemperatureInventory
    private let readFans: () -> [FanReading]
    private let snapshotBuilder = TelemetrySnapshotBuilder()
    private let managedFanConnection: SMCConnection?

    package init(inventory: TemperatureInventory = .loadDefault()) {
        self.inventory = inventory

        let connection = try? SMCConnection.open()
        self.managedFanConnection = connection
        self.readFans = {
            guard let connection else {
                return []
            }

            return (try? connection.readFans()) ?? []
        }
    }

    package init(
        inventory: TemperatureInventory,
        readFans: @escaping () -> [FanReading]
    ) {
        self.inventory = inventory
        self.readFans = readFans
        self.managedFanConnection = nil
    }

    deinit {
        managedFanConnection?.close()
    }

    package func refresh(
        previousSnapshot: TelemetrySnapshot? = nil,
        now: Date = Date()
    ) -> TelemetryCapture {
        let temperatures = inventory.refreshAll()
        let fans = readFans()

        return TelemetryCapture(
            temperatures: temperatures,
            fans: fans,
            snapshot: snapshotBuilder.build(
                refreshedAt: now,
                temperatures: temperatures,
                fans: fans,
                previousSnapshot: previousSnapshot
            )
        )
    }
}
