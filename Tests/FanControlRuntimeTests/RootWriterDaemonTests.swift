import Foundation
import XCTest
@testable import FanControlRuntime

final class RootWriterDaemonTests: XCTestCase {
    func testConflictingSessionsAreRejected() throws {
        let harness = try DaemonHarness()
        defer { harness.stop() }

        let writerA = try harness.connect()
        let writerB = try harness.connect()
        defer {
            try? writerA.shutdown()
            try? writerB.shutdown()
        }

        try writerA.applyTarget(fanIndex: 0, rpm: 3200)

        XCTAssertThrowsError(try writerB.applyTarget(fanIndex: 0, rpm: 2800)) { error in
            XCTAssertEqual(error as? FanWriterError, .conflict(fanIndex: 0))
        }
    }

    func testSessionShutdownRestoresManagedFans() throws {
        let harness = try DaemonHarness()
        defer { harness.stop() }

        let writer = try harness.connect()
        try writer.applyTarget(fanIndex: 0, rpm: 3300)

        let observerA = try harness.connect()
        defer { try? observerA.shutdown() }
        var beforeShutdown = try observerA.inspectFans()
        XCTAssertEqual(beforeShutdown.first?.targetRPM, 3300)
        XCTAssertEqual(beforeShutdown.first?.modeValue, 1)

        try writer.shutdown()

        let observerB = try harness.connect()
        defer { try? observerB.shutdown() }
        beforeShutdown = try observerB.inspectFans()
        XCTAssertNil(beforeShutdown.first?.targetRPM)
        XCTAssertEqual(beforeShutdown.first?.modeValue, 0)
        XCTAssertEqual(harness.store.restoreCalls, [0])
    }

    func testUnavailableDaemonReportsSocketPath() {
        XCTAssertThrowsError(try DaemonFanWriterClient.connect(socketPath: "/tmp/does-not-exist.sock")) { error in
            guard case let FanWriterError.daemonUnavailable(socketPath, _) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(socketPath, "/tmp/does-not-exist.sock")
        }
    }
}

private final class DaemonHarness: @unchecked Sendable {
    let store = FakeFanHardwareStore()
    private let tempDirectory: URL
    private let socketPath: String
    private let server: RootWriterDaemonServer
    private let thread: Thread

    init() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        socketPath = tempDirectory.appendingPathComponent("root-writer.sock").path
        let server = RootWriterDaemonServer(
            socketPath: socketPath,
            enforceRoot: false,
            makeConnection: { [store] in FakeFanHardware(store: store) }
        )
        self.server = server

        thread = Thread {
            try? server.run()
        }
        thread.start()
        try waitForSocket()
    }

    func connect() throws -> DaemonFanWriterClient {
        try DaemonFanWriterClient.connect(socketPath: socketPath)
    }

    func stop() {
        server.stop()
        while !thread.isFinished {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func waitForSocket() throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: socketPath) {
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        throw XCTSkip("daemon socket did not appear in time")
    }
}

private final class FakeFanHardwareStore: @unchecked Sendable {
    private let lock = NSLock()
    private var fans: [Int: FanReading] = [
        0: FanReading(index: 0, currentRPM: 2400, minimumRPM: 2000, maximumRPM: 5000, targetRPM: nil, modeValue: 0)
    ]
    private(set) var restoreCalls: [Int] = []

    func snapshot() -> [FanReading] {
        lock.lock()
        defer { lock.unlock() }
        return fans.keys.sorted().compactMap { fans[$0] }
    }

    func setManualMode(index: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard var fan = fans[index] else { return }
        fan = FanReading(
            index: fan.index,
            currentRPM: fan.currentRPM,
            minimumRPM: fan.minimumRPM,
            maximumRPM: fan.maximumRPM,
            targetRPM: fan.targetRPM,
            modeValue: 1
        )
        fans[index] = fan
    }

    func setTarget(index: Int, rpm: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard var fan = fans[index] else { return }
        fan = FanReading(
            index: fan.index,
            currentRPM: rpm,
            minimumRPM: fan.minimumRPM,
            maximumRPM: fan.maximumRPM,
            targetRPM: rpm,
            modeValue: fan.modeValue
        )
        fans[index] = fan
    }

    func restore(index: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard var fan = fans[index] else { return }
        fan = FanReading(
            index: fan.index,
            currentRPM: fan.minimumRPM,
            minimumRPM: fan.minimumRPM,
            maximumRPM: fan.maximumRPM,
            targetRPM: nil,
            modeValue: 0
        )
        fans[index] = fan
        restoreCalls.append(index)
    }
}

private final class FakeFanHardware: FanHardwareControlling {
    private let store: FakeFanHardwareStore

    init(store: FakeFanHardwareStore) {
        self.store = store
    }

    func readFans() throws -> [FanReading] {
        store.snapshot()
    }

    func setFanManualMode(index: Int) throws {
        store.setManualMode(index: index)
    }

    func setFanTargetRPM(index: Int, rpm: Int) throws {
        store.setTarget(index: index, rpm: rpm)
    }

    func restoreAutomaticMode(index: Int) throws {
        store.restore(index: index)
    }

    func close() {}
}
