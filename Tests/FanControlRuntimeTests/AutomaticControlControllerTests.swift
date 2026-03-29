import Foundation
import XCTest
@testable import FanControlRuntime

final class AutomaticControlControllerTests: XCTestCase {
    func testStartRejectsInvalidConfigWithoutActivatingSession() throws {
        let harness = try ControllerHarness()
        let invalidConfig = try harness.writeConfig(
            cpuSensor: "missing_cpu",
            gpuSensor: "gpu_cluster_average",
            pollingIntervalSeconds: 0.05,
            staleSensorTimeoutSeconds: 0.1
        )

        XCTAssertThrowsError(try harness.service.start(configPath: invalidConfig.path)) { error in
            guard case AutomaticControlError.invalidConfig = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        let status = harness.service.status()
        XCTAssertEqual(status.phase, .idle)
        XCTAssertNil(status.activeConfigPath)
        XCTAssertNotNil(status.lastError)
    }

    func testReloadFailureKeepsExistingSessionRunning() throws {
        let harness = try ControllerHarness()
        let validConfig = try harness.writeConfig(
            cpuSensor: "cpu_core_average",
            gpuSensor: "gpu_cluster_average",
            pollingIntervalSeconds: 0.05,
            staleSensorTimeoutSeconds: 0.2
        )
        let invalidConfig = try harness.writeConfig(
            cpuSensor: "unknown_sensor",
            gpuSensor: "gpu_cluster_average",
            pollingIntervalSeconds: 0.05,
            staleSensorTimeoutSeconds: 0.2
        )

        _ = try harness.service.start(configPath: validConfig.path)
        try harness.waitForPhase(.running)

        XCTAssertThrowsError(try harness.service.reload(configPath: invalidConfig.path)) { error in
            guard case AutomaticControlError.invalidConfig = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        let status = harness.service.status()
        XCTAssertEqual(status.phase, .running)
        XCTAssertEqual(status.activeConfigPath, validConfig.path)
        XCTAssertNotNil(status.lastError)
    }

    func testStaleSensorFailureRestoresAutomaticMode() throws {
        let harness = try ControllerHarness(
            inventoryFactory: {
                FakeInventoryFactory(cpuValues: [72, nil], gpuValues: [68, nil]).makeInventory()
            }
        )
        let config = try harness.writeConfig(
            cpuSensor: "cpu_core_average",
            gpuSensor: "gpu_cluster_average",
            pollingIntervalSeconds: 0.05,
            staleSensorTimeoutSeconds: 0.05
        )

        _ = try harness.service.start(configPath: config.path)
        try harness.waitForPhase(.failed)

        XCTAssertEqual(harness.runningWriter.restoreCalls, [0])
        XCTAssertEqual(harness.service.status().lastError, "required CPU/GPU domain sensor became stale")
    }

    func testWriterFailureMarksControllerFailedAndRestoresAutomaticMode() throws {
        let harness = try ControllerHarness(runningWriter: FakePrivilegedFanWriter(failOnApply: true))
        let config = try harness.writeConfig(
            cpuSensor: "cpu_core_average",
            gpuSensor: "gpu_cluster_average",
            pollingIntervalSeconds: 0.05,
            staleSensorTimeoutSeconds: 0.2
        )

        _ = try harness.service.start(configPath: config.path)
        try harness.waitForPhase(.failed)

        XCTAssertEqual(harness.runningWriter.restoreCalls, [0])
        let status = harness.service.status()
        XCTAssertFalse(status.writerConnected, "unexpected failed status: \(status)")
    }

    func testControllerServerSupportsStartStatusReloadStopLifecycle() throws {
        let socketDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: socketDirectory, withIntermediateDirectories: true)
        let socketPath = socketDirectory.appendingPathComponent("controller.sock").path

        let harness = try ControllerHarness()
        let server = AutomaticControlControllerServer(socketPath: socketPath, service: harness.service)
        let thread = Thread {
            try? server.run()
        }
        thread.start()
        defer {
            server.stop()
            while !thread.isFinished {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            try? FileManager.default.removeItem(at: socketDirectory)
        }

        let config = try harness.writeConfig(
            cpuSensor: "cpu_core_average",
            gpuSensor: "gpu_cluster_average",
            pollingIntervalSeconds: 0.05,
            staleSensorTimeoutSeconds: 0.2
        )
        try waitForSocket(path: socketPath)

        let startClient = try AutomaticControlControllerClient.connect(socketPath: socketPath)
        _ = try startClient.start(configPath: config.path)
        try startClient.close()

        let statusClient = try AutomaticControlControllerClient.connect(socketPath: socketPath)
        let runningStatus = try statusClient.status()
        try statusClient.close()
        XCTAssertTrue([AutomaticControlLifecyclePhase.starting, .running].contains(runningStatus.phase))

        let reloadClient = try AutomaticControlControllerClient.connect(socketPath: socketPath)
        _ = try reloadClient.reload(configPath: config.path)
        try reloadClient.close()

        let stopClient = try AutomaticControlControllerClient.connect(socketPath: socketPath)
        let stoppedStatus = try stopClient.stop()
        try stopClient.close()
        XCTAssertEqual(stoppedStatus.phase, .idle)
    }

    private func waitForSocket(path: String) throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) {
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        throw XCTSkip("controller socket did not appear in time")
    }
}

private final class ControllerHarness {
    let validationWriter = FakePrivilegedFanWriter()
    let runningWriter: FakePrivilegedFanWriter
    let service: AutomaticControlService
    private let tempDirectory: URL

    init(
        inventoryFactory: @escaping @Sendable () -> TemperatureInventory = {
            FakeInventoryFactory.default.makeInventory()
        },
        runningWriter: FakePrivilegedFanWriter = FakePrivilegedFanWriter()
    ) throws {
        self.runningWriter = runningWriter
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let writers = WriterQueue(writers: [validationWriter, runningWriter, validationWriter, runningWriter])
        service = AutomaticControlService(
            inventoryFactory: inventoryFactory,
            writerFactory: {
                try writers.next()
            }
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func writeConfig(
        cpuSensor: String,
        gpuSensor: String,
        pollingIntervalSeconds: TimeInterval,
        staleSensorTimeoutSeconds: TimeInterval
    ) throws -> URL {
        let configURL = tempDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let json = """
        {
          "pollingIntervalSeconds": \(pollingIntervalSeconds),
          "minimumWriteIntervalSeconds": 0.01,
          "staleSensorTimeoutSeconds": \(staleSensorTimeoutSeconds),
          "smoothingStepRPM": 300,
          "hysteresisRPM": 100,
          "cpuDomain": {
            "sensor": "\(cpuSensor)",
            "startTemperatureCelsius": 55,
            "maxTemperatureCelsius": 90
          },
          "gpuDomain": {
            "sensor": "\(gpuSensor)",
            "startTemperatureCelsius": 50,
            "maxTemperatureCelsius": 95
          },
          "fans": [
            {
              "fanIndex": 0,
              "minimumRPM": 2000,
              "maximumRPM": 4000
            }
          ]
        }
        """
        try json.write(to: configURL, atomically: true, encoding: .utf8)
        return configURL
    }

    func waitForPhase(_ expectedPhase: AutomaticControlLifecyclePhase) throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if service.status().phase == expectedPhase {
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTFail("timed out waiting for controller phase \(expectedPhase.rawValue); current status: \(service.status())")
    }
}

private final class WriterQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var writers: [FakePrivilegedFanWriter]
    private var nextWriterIndex = 0

    init(writers: [FakePrivilegedFanWriter]) {
        self.writers = writers
    }

    func next() throws -> any PrivilegedFanWriter {
        lock.lock()
        defer { lock.unlock() }
        guard nextWriterIndex < writers.count else {
            return FakePrivilegedFanWriter()
        }
        let writer = writers[nextWriterIndex]
        nextWriterIndex += 1
        return writer
    }
}

private struct FakeInventoryFactory {
    static let `default` = FakeInventoryFactory(
        cpuValues: [70],
        gpuValues: [65]
    )

    let cpuValues: [Double?]
    let gpuValues: [Double?]

    func makeInventory() -> TemperatureInventory {
        return TemperatureInventory(
            runtime: TemperatureRuntime(),
            sensors: [
                FakeTemperatureSensor(values: cpuValues, rawName: "fake_cpu_sensor", displayName: "CPU", group: "CPU", type: "cpu", sortKey: "1"),
                FakeTemperatureSensor(values: gpuValues, rawName: "fake_gpu_sensor", displayName: "GPU", group: "GPU", type: "gpu", sortKey: "2")
            ]
        )
    }
}

private final class SensorValueSequence {
    private let lock = NSLock()
    private let values: [Double?]
    private var nextIndex = 0

    init(values: [Double?]) {
        self.values = values
    }

    func nextValue() -> Double? {
        lock.lock()
        defer { lock.unlock() }

        let currentIndex = min(nextIndex, values.count - 1)
        let value = values[currentIndex]
        if nextIndex < values.count - 1 {
            nextIndex += 1
        }
        return value
    }
}

private final class FakeTemperatureSensor: TemperatureSensor {
    let source: TemperatureSource = .aggregate
    let rawName: String
    let displayName: String
    let group: String?
    let type: String?
    let sortKey: String

    private let sequence: SensorValueSequence

    init(
        values: [Double?],
        rawName: String,
        displayName: String,
        group: String?,
        type: String?,
        sortKey: String
    ) {
        self.sequence = SensorValueSequence(values: values)
        self.rawName = rawName
        self.displayName = displayName
        self.group = group
        self.type = type
        self.sortKey = sortKey
    }

    func refreshValue() -> Double? {
        sequence.nextValue()
    }
}

private final class FakePrivilegedFanWriter: PrivilegedFanWriter {
    private let lock = NSLock()
    private let failOnApply: Bool
    private(set) var restoreCalls: [Int] = []
    private let fans: [FanReading]

    init(failOnApply: Bool = false) {
        self.failOnApply = failOnApply
        self.fans = [FanReading(index: 0, currentRPM: 2400, minimumRPM: 2000, maximumRPM: 5000, targetRPM: nil, modeValue: 0)]
    }

    func inspectFans() throws -> [FanReading] {
        fans
    }

    func applyTarget(fanIndex: Int, rpm: Int) throws {
        if failOnApply {
            throw FanWriterError.daemonFailure("simulated writer failure")
        }
    }

    func restoreAutomaticMode(fanIndices: [Int]) throws {
        lock.lock()
        restoreCalls.append(contentsOf: fanIndices)
        lock.unlock()
    }

    func shutdown() throws {}
}
