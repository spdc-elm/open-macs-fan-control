import XCTest
@testable import FanControlRuntime

final class AutomaticControlTests: XCTestCase {
    func testCpuDemandDominatesRequestedTarget() {
        let config = makeResolvedConfig()
        let resolver = AutomaticControlResolver(config: config)
        let plan = resolver.demandPlan(
            for: DomainSnapshot(cpuTemperatureCelsius: 85, gpuTemperatureCelsius: 62),
            fan: config.fans[0]
        )

        XCTAssertGreaterThan(plan.cpuDemandRPM, plan.gpuDemandRPM)
        XCTAssertEqual(plan.requestedTargetRPM, plan.cpuDemandRPM)
    }

    func testGpuDemandDominatesRequestedTarget() {
        let config = makeResolvedConfig()
        let resolver = AutomaticControlResolver(config: config)
        let plan = resolver.demandPlan(
            for: DomainSnapshot(cpuTemperatureCelsius: 60, gpuTemperatureCelsius: 88),
            fan: config.fans[0]
        )

        XCTAssertGreaterThan(plan.gpuDemandRPM, plan.cpuDemandRPM)
        XCTAssertEqual(plan.requestedTargetRPM, plan.gpuDemandRPM)
    }

    func testSmoothingAndWriteThrottleSuppressChatter() {
        var state = FanControlState(lastAppliedRPM: 2400, lastWriteAt: Date(timeIntervalSince1970: 0))

        let earlyTarget = state.nextWriteTarget(
            requestedRPM: 3200,
            now: Date(timeIntervalSince1970: 1),
            smoothingStepRPM: 300,
            hysteresisRPM: 100,
            minimumWriteInterval: 2
        )
        XCTAssertNil(earlyTarget)

        let laterTarget = state.nextWriteTarget(
            requestedRPM: 3200,
            now: Date(timeIntervalSince1970: 3),
            smoothingStepRPM: 300,
            hysteresisRPM: 100,
            minimumWriteInterval: 2
        )
        XCTAssertEqual(laterTarget, 2700)
    }

    func testResolveSnapshotIgnoresUnrelatedDuplicateRawNames() throws {
        let config = makeResolvedConfig()
        let resolver = AutomaticControlResolver(config: config)
        let readings = [
            UnifiedTemperatureReading(source: .smc, rawName: "PMU tcal", displayName: "PMU A", valueCelsius: 40, group: nil, type: nil, sortKey: "1"),
            UnifiedTemperatureReading(source: .iohid, rawName: "PMU tcal", displayName: "PMU B", valueCelsius: 41, group: nil, type: nil, sortKey: "2"),
            UnifiedTemperatureReading(source: .aggregate, rawName: "cpu_core_average", displayName: "CPU", valueCelsius: 72, group: "CPU", type: "cpu", sortKey: "3"),
            UnifiedTemperatureReading(source: .aggregate, rawName: "gpu_cluster_average", displayName: "GPU", valueCelsius: 68, group: "GPU", type: "gpu", sortKey: "4")
        ]

        let snapshot = try resolver.resolveSnapshot(from: readings)
        XCTAssertEqual(snapshot.cpuTemperatureCelsius, 72)
        XCTAssertEqual(snapshot.gpuTemperatureCelsius, 68)
    }

    func testResolveSnapshotRejectsAmbiguousConfiguredSensor() {
        let config = makeResolvedConfig()
        let resolver = AutomaticControlResolver(config: config)
        let readings = [
            UnifiedTemperatureReading(source: .aggregate, rawName: "cpu_core_average", displayName: "CPU 1", valueCelsius: 70, group: "CPU", type: "cpu", sortKey: "1"),
            UnifiedTemperatureReading(source: .aggregate, rawName: "cpu_core_average", displayName: "CPU 2", valueCelsius: 71, group: "CPU", type: "cpu", sortKey: "2"),
            UnifiedTemperatureReading(source: .aggregate, rawName: "gpu_cluster_average", displayName: "GPU", valueCelsius: 68, group: "GPU", type: "gpu", sortKey: "3")
        ]

        XCTAssertThrowsError(try resolver.resolveSnapshot(from: readings)) { error in
            guard case AutomaticControlError.ambiguousSensor("cpu_core_average", 2) = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    private func makeResolvedConfig() -> ResolvedAutomaticControlConfig {
        ResolvedAutomaticControlConfig(
            sourcePath: "/tmp/test.json",
            pollingIntervalSeconds: 1,
            minimumWriteIntervalSeconds: 2,
            staleSensorTimeoutSeconds: 5,
            smoothingStepRPM: 300,
            hysteresisRPM: 100,
            cpuDomain: ThermalDomainConfig(sensor: "cpu_core_average", startTemperatureCelsius: 55, maxTemperatureCelsius: 90),
            gpuDomain: ThermalDomainConfig(sensor: "gpu_cluster_average", startTemperatureCelsius: 50, maxTemperatureCelsius: 95),
            fans: [
                ResolvedFanPolicy(
                    fanIndex: 0,
                    minimumRPM: 2000,
                    maximumRPM: 5000,
                    hardwareMinimumRPM: 1800,
                    hardwareMaximumRPM: 5500
                )
            ]
        )
    }
}
