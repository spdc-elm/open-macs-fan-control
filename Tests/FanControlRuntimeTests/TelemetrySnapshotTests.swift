import XCTest
@testable import FanControlRuntime

final class TelemetrySnapshotTests: XCTestCase {
    func testBuilderUsesAggregateCpuGpuAndFanAverage() {
        let refreshedAt = Date(timeIntervalSince1970: 100)
        let snapshot = TelemetrySnapshotBuilder().build(
            refreshedAt: refreshedAt,
            temperatures: [
                UnifiedTemperatureReading(source: .aggregate, rawName: "cpu_core_average", displayName: "CPU", valueCelsius: 71.5, group: "CPU", type: "cpu", sortKey: "1"),
                UnifiedTemperatureReading(source: .aggregate, rawName: "gpu_cluster_average", displayName: "GPU", valueCelsius: 63.0, group: "GPU", type: "gpu", sortKey: "2")
            ],
            fans: [
                FanReading(index: 0, currentRPM: 1800, minimumRPM: 1200, maximumRPM: 4000, targetRPM: nil, modeValue: 0),
                FanReading(index: 1, currentRPM: 2200, minimumRPM: 1200, maximumRPM: 4000, targetRPM: nil, modeValue: 0)
            ]
        )

        XCTAssertEqual(snapshot.cpuAverageCelsius.state, .live)
        XCTAssertEqual(snapshot.cpuAverageCelsius.value, 71.5)
        XCTAssertEqual(snapshot.gpuAverageCelsius.state, .live)
        XCTAssertEqual(snapshot.gpuAverageCelsius.value, 63.0)
        XCTAssertEqual(snapshot.fanSummary.state, .live)
        XCTAssertEqual(snapshot.fanSummary.averageCurrentRPM, 2000)
        XCTAssertEqual(snapshot.fanSummary.minimumCurrentRPM, 1800)
        XCTAssertEqual(snapshot.fanSummary.maximumCurrentRPM, 2200)
        XCTAssertEqual(snapshot.fanSummary.lastUpdatedAt, refreshedAt)
    }

    func testBuilderMarksMissingSignalsUnavailableWithoutPreviousSnapshot() {
        let snapshot = TelemetrySnapshotBuilder().build(
            refreshedAt: Date(timeIntervalSince1970: 100),
            temperatures: [],
            fans: []
        )

        XCTAssertEqual(snapshot.cpuAverageCelsius.state, .unavailable)
        XCTAssertNil(snapshot.cpuAverageCelsius.value)
        XCTAssertEqual(snapshot.gpuAverageCelsius.state, .unavailable)
        XCTAssertEqual(snapshot.fanSummary.state, .unavailable)
        XCTAssertTrue(snapshot.hasUnavailableSignals)
    }

    func testBuilderPreservesPreviousSuccessfulValuesAsStale() {
        let previous = TelemetrySnapshotBuilder().build(
            refreshedAt: Date(timeIntervalSince1970: 100),
            temperatures: [
                UnifiedTemperatureReading(source: .aggregate, rawName: "cpu_core_average", displayName: "CPU", valueCelsius: 70, group: "CPU", type: "cpu", sortKey: "1"),
                UnifiedTemperatureReading(source: .aggregate, rawName: "gpu_cluster_average", displayName: "GPU", valueCelsius: 60, group: "GPU", type: "gpu", sortKey: "2")
            ],
            fans: [
                FanReading(index: 0, currentRPM: 1900, minimumRPM: 1200, maximumRPM: 4000, targetRPM: nil, modeValue: 0)
            ]
        )

        let stale = TelemetrySnapshotBuilder().build(
            refreshedAt: Date(timeIntervalSince1970: 200),
            temperatures: [],
            fans: [],
            previousSnapshot: previous
        )

        XCTAssertEqual(stale.cpuAverageCelsius.state, .stale)
        XCTAssertEqual(stale.cpuAverageCelsius.value, 70)
        XCTAssertEqual(stale.cpuAverageCelsius.lastUpdatedAt, previous.cpuAverageCelsius.lastUpdatedAt)
        XCTAssertEqual(stale.gpuAverageCelsius.state, .stale)
        XCTAssertEqual(stale.fanSummary.state, .stale)
        XCTAssertEqual(stale.fanSummary.averageCurrentRPM, 1900)
        XCTAssertTrue(stale.hasStaleSignals)
    }
}
