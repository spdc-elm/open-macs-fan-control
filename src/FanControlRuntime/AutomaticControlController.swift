import Darwin
import Foundation

package enum AutomaticControlLifecyclePhase: String, Codable {
    case idle
    case starting
    case running
    case stopping
    case failed
}

package struct AutomaticControlFanStatus: Codable, Equatable {
    package let fanIndex: Int
    package let lastRequestedRPM: Int?
    package let lastAppliedRPM: Int?
    package let lastWriteAt: Date?
}

package struct AutomaticControlStatusSnapshot: Codable, Equatable {
    package let phase: AutomaticControlLifecyclePhase
    package let activeConfigPath: String?
    package let lastSampleAt: Date?
    package let lastSuccessfulSampleAt: Date?
    package let writerConnected: Bool
    package let fans: [AutomaticControlFanStatus]
    package let lastError: String?

    package static func idle(lastError: String? = nil) -> AutomaticControlStatusSnapshot {
        AutomaticControlStatusSnapshot(
            phase: .idle,
            activeConfigPath: nil,
            lastSampleAt: nil,
            lastSuccessfulSampleAt: nil,
            writerConnected: false,
            fans: [],
            lastError: lastError
        )
    }
}

private enum AutomaticControlSessionError: LocalizedError {
    case staleSensorTimeout

    var errorDescription: String? {
        switch self {
        case .staleSensorTimeout:
            return "required thermal domain sensor became stale"
        }
    }
}

package enum AutomaticControlControllerPaths {
    private static let baseDirectory = NSHomeDirectory() + "/Library/Application Support/macs-fan-control"
    package static let socketPath = baseDirectory + "/fan-control-controller.sock"
    package static let logPath = baseDirectory + "/fan-control-controller.log"
}

package enum AutomaticControlControllerError: LocalizedError, Equatable {
    case controllerUnavailable(socketPath: String, reason: String)
    case invalidRequest(String)
    case protocolViolation(String)
    case controllerFailure(String)

    package var errorDescription: String? {
        switch self {
        case .controllerUnavailable(let socketPath, let reason):
            return "automatic-control controller is unavailable at \(socketPath): \(reason)"
        case .invalidRequest(let message):
            return message
        case .protocolViolation(let message):
            return "controller protocol error: \(message)"
        case .controllerFailure(let message):
            return message
        }
    }
}

package enum AutomaticControlControllerCommand: String, Codable {
    case start
    case stop
    case reload
    case status
}

package struct AutomaticControlControllerRequest: Codable {
    package let command: AutomaticControlControllerCommand
    package let configPath: String?

    package init(command: AutomaticControlControllerCommand, configPath: String? = nil) {
        self.command = command
        self.configPath = configPath
    }
}

package struct AutomaticControlControllerResponse: Codable {
    package let ok: Bool
    package let errorCode: String?
    package let errorMessage: String?
    package let status: AutomaticControlStatusSnapshot?

    package static func success(_ status: AutomaticControlStatusSnapshot) -> AutomaticControlControllerResponse {
        AutomaticControlControllerResponse(ok: true, errorCode: nil, errorMessage: nil, status: status)
    }

    package static func failure(code: String, message: String, status: AutomaticControlStatusSnapshot?) -> AutomaticControlControllerResponse {
        AutomaticControlControllerResponse(ok: false, errorCode: code, errorMessage: message, status: status)
    }
}

private enum AutomaticControlSessionOutcome {
    case stopped
    case failed(Error)
}

private final class AutomaticControlSession: @unchecked Sendable {
    private let config: ResolvedAutomaticControlConfig
    private let inventory: TemperatureInventory
    private let writer: any PrivilegedFanWriter
    private let statusHandler: @Sendable (AutomaticControlStatusSnapshot) -> Void
    private let completion: @Sendable (AutomaticControlSessionOutcome) -> Void
    private let lifecycleLock = NSLock()
    private var stopRequested = false
    private var thread: Thread?

    init(
        config: ResolvedAutomaticControlConfig,
        inventory: TemperatureInventory,
        writer: any PrivilegedFanWriter,
        statusHandler: @escaping @Sendable (AutomaticControlStatusSnapshot) -> Void,
        completion: @escaping @Sendable (AutomaticControlSessionOutcome) -> Void
    ) {
        self.config = config
        self.inventory = inventory
        self.writer = writer
        self.statusHandler = statusHandler
        self.completion = completion
    }

    func start() {
        let thread = Thread { [self] in
            runLoop()
        }
        lifecycleLock.lock()
        self.thread = thread
        lifecycleLock.unlock()
        thread.start()
    }

    func requestStop() {
        lifecycleLock.lock()
        stopRequested = true
        lifecycleLock.unlock()
    }

    func waitUntilFinished() {
        while true {
            lifecycleLock.lock()
            let thread = self.thread
            lifecycleLock.unlock()

            guard let thread else {
                return
            }
            if thread.isFinished {
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private func runLoop() {
        let resolver = AutomaticControlResolver(config: config)
        var fanStates = Dictionary(uniqueKeysWithValues: config.fans.map { ($0.fanIndex, FanControlState()) })
        var lastRequestedTargets: [Int: Int] = [:]
        var lastSampleAt: Date?
        var lastSuccessfulSampleAt = Date()

        statusHandler(
            makeStatus(
                phase: .running,
                fanStates: fanStates,
                lastRequestedTargets: lastRequestedTargets,
                lastSampleAt: nil,
                lastSuccessfulSampleAt: nil,
                lastError: nil,
                writerConnected: true
            )
        )

        do {
            while true {
                if isStopRequested {
                    statusHandler(
                        makeStatus(
                            phase: .stopping,
                            fanStates: fanStates,
                            lastRequestedTargets: lastRequestedTargets,
                            lastSampleAt: lastSampleAt,
                            lastSuccessfulSampleAt: lastSuccessfulSampleAt,
                            lastError: nil,
                            writerConnected: true
                        )
                    )
                    break
                }

                let now = Date()
                lastSampleAt = now
                let readings = inventory.refreshAll()
                if let snapshot = try? resolver.resolveSnapshot(from: readings) {
                    lastSuccessfulSampleAt = now
                    try applyCycle(
                        config: config,
                        snapshot: snapshot,
                        resolver: resolver,
                        fanStates: &fanStates,
                        lastRequestedTargets: &lastRequestedTargets,
                        writer: writer
                    )
                    statusHandler(
                        makeStatus(
                            phase: .running,
                            fanStates: fanStates,
                            lastRequestedTargets: lastRequestedTargets,
                            lastSampleAt: lastSampleAt,
                            lastSuccessfulSampleAt: lastSuccessfulSampleAt,
                            lastError: nil,
                            writerConnected: true
                        )
                    )
                } else if now.timeIntervalSince(lastSuccessfulSampleAt) >= config.staleSensorTimeoutSeconds {
                    throw AutomaticControlSessionError.staleSensorTimeout
                } else {
                    statusHandler(
                        makeStatus(
                            phase: .running,
                            fanStates: fanStates,
                            lastRequestedTargets: lastRequestedTargets,
                            lastSampleAt: lastSampleAt,
                            lastSuccessfulSampleAt: lastSuccessfulSampleAt,
                            lastError: nil,
                            writerConnected: true
                        )
                    )
                }

                Thread.sleep(forTimeInterval: config.pollingIntervalSeconds)
            }

            try writer.restoreAutomaticMode(fanIndices: config.fans.map(\.fanIndex))
            completion(.stopped)
        } catch {
            try? writer.restoreAutomaticMode(fanIndices: config.fans.map(\.fanIndex))
            statusHandler(
                makeStatus(
                    phase: .failed,
                    fanStates: fanStates,
                    lastRequestedTargets: lastRequestedTargets,
                    lastSampleAt: lastSampleAt,
                    lastSuccessfulSampleAt: lastSuccessfulSampleAt,
                    lastError: error.localizedDescription,
                    writerConnected: !isWriterFailure(error),
                    keepConfigPath: true
                )
            )
            completion(.failed(error))
        }

        try? writer.shutdown()
    }

    private var isStopRequested: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return stopRequested
    }

    private func makeStatus(
        phase: AutomaticControlLifecyclePhase,
        fanStates: [Int: FanControlState],
        lastRequestedTargets: [Int: Int],
        lastSampleAt: Date?,
        lastSuccessfulSampleAt: Date?,
        lastError: String?,
        writerConnected: Bool,
        keepConfigPath: Bool = true
    ) -> AutomaticControlStatusSnapshot {
        let fans = config.fans.map { fan in
            let state = fanStates[fan.fanIndex]
            return AutomaticControlFanStatus(
                fanIndex: fan.fanIndex,
                lastRequestedRPM: lastRequestedTargets[fan.fanIndex],
                lastAppliedRPM: state?.lastAppliedRPM,
                lastWriteAt: state?.lastWriteAt
            )
        }

        return AutomaticControlStatusSnapshot(
            phase: phase,
            activeConfigPath: keepConfigPath ? config.sourcePath : nil,
            lastSampleAt: lastSampleAt,
            lastSuccessfulSampleAt: lastSuccessfulSampleAt,
            writerConnected: writerConnected,
            fans: fans,
            lastError: lastError
        )
    }

    private func applyCycle(
        config: ResolvedAutomaticControlConfig,
        snapshot: DomainSnapshot,
        resolver: AutomaticControlResolver,
        fanStates: inout [Int: FanControlState],
        lastRequestedTargets: inout [Int: Int],
        writer: any PrivilegedFanWriter
    ) throws {
        let now = Date()

        for fan in config.fans {
            let plan = resolver.demandPlan(for: snapshot, fan: fan)
            lastRequestedTargets[fan.fanIndex] = plan.requestedTargetRPM

            var state = fanStates[fan.fanIndex] ?? FanControlState()
            guard let targetRPM = state.nextWriteTarget(
                requestedRPM: plan.requestedTargetRPM,
                now: now,
                smoothingStepRPM: config.smoothingStepRPM,
                hysteresisRPM: config.hysteresisRPM,
                minimumWriteInterval: config.minimumWriteIntervalSeconds
            ) else {
                fanStates[fan.fanIndex] = state
                continue
            }

            try writer.applyTarget(fanIndex: fan.fanIndex, rpm: targetRPM)
            state.recordWrite(targetRPM: targetRPM, at: now)
            fanStates[fan.fanIndex] = state
        }
    }

    private func isWriterFailure(_ error: Error) -> Bool {
        if error is FanWriterError {
            return true
        }
        if let automaticControlError = error as? AutomaticControlError, case .writer = automaticControlError {
            return true
        }
        return error.localizedDescription.localizedCaseInsensitiveContains("writer")
    }
}

package final class AutomaticControlService: @unchecked Sendable {
    private let inventoryFactory: @Sendable () -> TemperatureInventory
    private let writerFactory: @Sendable () throws -> any PrivilegedFanWriter
    private let stateLock = NSLock()
    private var session: AutomaticControlSession?
    private var statusSnapshot = AutomaticControlStatusSnapshot.idle()

    package init(
        inventoryFactory: @escaping @Sendable () -> TemperatureInventory = { TemperatureInventory.loadDefault() },
        writerFactory: @escaping @Sendable () throws -> any PrivilegedFanWriter = { try DaemonFanWriterClient.connect() }
    ) {
        self.inventoryFactory = inventoryFactory
        self.writerFactory = writerFactory
    }

    package func status() -> AutomaticControlStatusSnapshot {
        stateLock.lock()
        defer { stateLock.unlock() }
        return statusSnapshot
    }

    package func start(configPath: String) throws -> AutomaticControlStatusSnapshot {
        stateLock.lock()
        let currentlyRunning = session != nil
        stateLock.unlock()

        guard !currentlyRunning else {
            throw AutomaticControlControllerError.invalidRequest("automatic control is already running; use `fan-control-cli auto reload --config <path>` or `fan-control-cli auto stop`")
        }

        let resolved = try prepareResolvedConfig(from: configPath)
        try startSession(with: resolved)
        return status()
    }

    package func reload(configPath: String) throws -> AutomaticControlStatusSnapshot {
        let resolved = try prepareResolvedConfig(from: configPath)
        if hasActiveSession {
            try stopInternal()
        }
        try startSession(with: resolved)
        return status()
    }

    package func stop() throws -> AutomaticControlStatusSnapshot {
        try stopInternal()
        return status()
    }

    private var hasActiveSession: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return session != nil
    }

    private func prepareResolvedConfig(from configPath: String) throws -> ResolvedAutomaticControlConfig {
        let inventory = inventoryFactory()
        let writer = try writerFactory()
        defer { try? writer.shutdown() }

        let bootstrap = AutomaticControlBootstrap(inventory: inventory, writer: writer)
        do {
            return try bootstrap.loadResolvedConfig(from: configPath)
        } catch {
            recordRecoverableFailure(error)
            throw error
        }
    }

    private func startSession(with config: ResolvedAutomaticControlConfig) throws {
        let writer: any PrivilegedFanWriter
        do {
            writer = try writerFactory()
        } catch {
            recordRecoverableFailure(error)
            throw error
        }

        let session = AutomaticControlSession(
            config: config,
            inventory: inventoryFactory(),
            writer: writer,
            statusHandler: { [weak self] status in
                self?.replaceStatus(status)
            },
            completion: { [weak self] outcome in
                self?.finishSession(outcome)
            }
        )

        stateLock.lock()
        statusSnapshot = AutomaticControlStatusSnapshot(
            phase: .starting,
            activeConfigPath: config.sourcePath,
            lastSampleAt: nil,
            lastSuccessfulSampleAt: nil,
            writerConnected: true,
            fans: config.fans.map {
                AutomaticControlFanStatus(fanIndex: $0.fanIndex, lastRequestedRPM: nil, lastAppliedRPM: nil, lastWriteAt: nil)
            },
            lastError: nil
        )
        self.session = session
        stateLock.unlock()

        session.start()
    }

    private func stopInternal() throws {
        stateLock.lock()
        guard let session else {
            statusSnapshot = AutomaticControlStatusSnapshot.idle(lastError: statusSnapshot.lastError)
            stateLock.unlock()
            return
        }
        let status = statusSnapshot
        statusSnapshot = AutomaticControlStatusSnapshot(
            phase: .stopping,
            activeConfigPath: status.activeConfigPath,
            lastSampleAt: status.lastSampleAt,
            lastSuccessfulSampleAt: status.lastSuccessfulSampleAt,
            writerConnected: status.writerConnected,
            fans: status.fans,
            lastError: status.lastError
        )
        stateLock.unlock()

        session.requestStop()
        session.waitUntilFinished()
    }

    private func replaceStatus(_ status: AutomaticControlStatusSnapshot) {
        stateLock.lock()
        statusSnapshot = status
        stateLock.unlock()
    }

    private func finishSession(_ outcome: AutomaticControlSessionOutcome) {
        stateLock.lock()
        session = nil
        switch outcome {
        case .stopped:
            statusSnapshot = AutomaticControlStatusSnapshot.idle(lastError: nil)
        case .failed(let error):
            let existing = statusSnapshot
            statusSnapshot = AutomaticControlStatusSnapshot(
                phase: .failed,
                activeConfigPath: existing.activeConfigPath,
                lastSampleAt: existing.lastSampleAt,
                lastSuccessfulSampleAt: existing.lastSuccessfulSampleAt,
                writerConnected: existing.writerConnected && !(error is FanWriterError),
                fans: existing.fans,
                lastError: error.localizedDescription
            )
        }
        stateLock.unlock()
    }

    private func recordRecoverableFailure(_ error: Error) {
        stateLock.lock()
        let existing = statusSnapshot
        statusSnapshot = AutomaticControlStatusSnapshot(
            phase: session == nil ? .idle : existing.phase,
            activeConfigPath: existing.activeConfigPath,
            lastSampleAt: existing.lastSampleAt,
            lastSuccessfulSampleAt: existing.lastSuccessfulSampleAt,
            writerConnected: !(error is FanWriterError),
            fans: existing.fans,
            lastError: error.localizedDescription
        )
        stateLock.unlock()
    }
}

private func controllerLog(_ message: String) {
    let line = "[fan-control-controller] \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
}

package final class AutomaticControlControllerServer: @unchecked Sendable {
    private let socketPath: String
    private let service: AutomaticControlService
    private let lifecycleLock = NSLock()
    private var listenerDescriptor: Int32?
    private var shutdownRequested = false

    package init(
        socketPath: String = AutomaticControlControllerPaths.socketPath,
        service: AutomaticControlService = AutomaticControlService()
    ) {
        self.socketPath = socketPath
        self.service = service
    }

    package func run() throws {
        signal(SIGPIPE, SIG_IGN)

        let fileManager = FileManager.default
        let socketDirectory = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        try fileManager.createDirectory(at: URL(fileURLWithPath: socketDirectory, isDirectory: true), withIntermediateDirectories: true)
        if chmod(socketDirectory, 0o755) != 0 {
            throw RuntimeCommandError("failed to set controller socket directory permissions at \(socketDirectory): \(String(cString: strerror(errno)))")
        }

        let listener = try LocalSocket.makeListener(path: socketPath, permissions: 0o600)
        lifecycleLock.lock()
        listenerDescriptor = listener
        shutdownRequested = false
        lifecycleLock.unlock()
        defer {
            lifecycleLock.lock()
            listenerDescriptor = nil
            lifecycleLock.unlock()
            close(listener)
            unlink(socketPath)
            _ = try? service.stop()
        }

        controllerLog("listening at \(socketPath)")
        let signalMonitor = SignalMonitor()
        defer { signalMonitor.stop() }

        while !signalMonitor.terminationRequested && !isShutdownRequested {
            let descriptor: Int32
            do {
                descriptor = try LocalSocket.accept(from: listener)
            } catch {
                if signalMonitor.terminationRequested || isShutdownRequested {
                    break
                }
                throw error
            }

            Thread.detachNewThread { [service, socketPath] in
                AutomaticControlControllerConnection(
                    descriptor: descriptor,
                    socketPath: socketPath,
                    service: service
                ).run()
            }
        }
    }

    package func stop() {
        lifecycleLock.lock()
        shutdownRequested = true
        let listener = listenerDescriptor
        listenerDescriptor = nil
        lifecycleLock.unlock()

        guard let listener else {
            return
        }

        if let descriptor = try? LocalSocket.connect(to: socketPath) {
            close(descriptor)
        }
        Darwin.shutdown(listener, SHUT_RDWR)
        close(listener)
    }

    private var isShutdownRequested: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return shutdownRequested
    }
}

private final class AutomaticControlControllerConnection {
    private let descriptor: Int32
    private let socketPath: String
    private let service: AutomaticControlService
    private let lineReader: PipeLineReader
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(descriptor: Int32, socketPath: String, service: AutomaticControlService) {
        self.descriptor = descriptor
        self.socketPath = socketPath
        self.service = service
        self.lineReader = PipeLineReader(descriptor: descriptor)
    }

    func run() {
        defer {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            close(descriptor)
        }

        guard let line = try? lineReader.readLine() else {
            return
        }

        let response: AutomaticControlControllerResponse
        do {
            let request = try decoder.decode(AutomaticControlControllerRequest.self, from: Data(line.utf8))
            response = try handle(request)
        } catch let error as AutomaticControlControllerError {
            response = .failure(code: "controller", message: error.localizedDescription, status: service.status())
        } catch let error as AutomaticControlError {
            response = .failure(code: "invalid_request", message: error.localizedDescription, status: service.status())
        } catch {
            response = .failure(code: "controller", message: error.localizedDescription, status: service.status())
        }

        do {
            let data = try encoder.encode(response)
            try LocalSocket.writeAll(data, to: descriptor)
            try LocalSocket.writeAll(Data([0x0a]), to: descriptor)
        } catch {
            controllerLog("failed to reply to controller client at \(socketPath): \(error.localizedDescription)")
        }
    }

    private func handle(_ request: AutomaticControlControllerRequest) throws -> AutomaticControlControllerResponse {
        let status: AutomaticControlStatusSnapshot
        switch request.command {
        case .start:
            guard let configPath = request.configPath, !configPath.isEmpty else {
                throw AutomaticControlControllerError.invalidRequest("controller start requires a config path")
            }
            status = try service.start(configPath: configPath)
        case .reload:
            guard let configPath = request.configPath, !configPath.isEmpty else {
                throw AutomaticControlControllerError.invalidRequest("controller reload requires a config path")
            }
            status = try service.reload(configPath: configPath)
        case .stop:
            status = try service.stop()
        case .status:
            status = service.status()
        }
        return .success(status)
    }
}

package final class AutomaticControlControllerClient {
    private let socketPath: String
    private let descriptor: Int32
    private let lineReader: PipeLineReader
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isClosed = false

    private init(socketPath: String, descriptor: Int32) {
        self.socketPath = socketPath
        self.descriptor = descriptor
        self.lineReader = PipeLineReader(descriptor: descriptor)
    }

    deinit {
        try? closeConnection()
    }

    package static func connect(socketPath: String = AutomaticControlControllerPaths.socketPath) throws -> AutomaticControlControllerClient {
        let descriptor: Int32
        do {
            descriptor = try LocalSocket.connect(to: socketPath)
        } catch let error as FanWriterError {
            throw AutomaticControlControllerError.controllerUnavailable(socketPath: socketPath, reason: error.localizedDescription)
        } catch {
            throw AutomaticControlControllerError.controllerUnavailable(socketPath: socketPath, reason: error.localizedDescription)
        }

        return AutomaticControlControllerClient(socketPath: socketPath, descriptor: descriptor)
    }

    package func start(configPath: String) throws -> AutomaticControlStatusSnapshot {
        try send(.init(command: .start, configPath: configPath))
    }

    package func reload(configPath: String) throws -> AutomaticControlStatusSnapshot {
        try send(.init(command: .reload, configPath: configPath))
    }

    package func stop() throws -> AutomaticControlStatusSnapshot {
        try send(.init(command: .stop))
    }

    package func status() throws -> AutomaticControlStatusSnapshot {
        try send(.init(command: .status))
    }

    package func close() throws {
        try closeConnection()
    }

    private func send(_ request: AutomaticControlControllerRequest) throws -> AutomaticControlStatusSnapshot {
        guard !isClosed else {
            throw AutomaticControlControllerError.controllerUnavailable(socketPath: socketPath, reason: "client session is already closed")
        }

        do {
            let data = try encoder.encode(request)
            try LocalSocket.writeAll(data, to: descriptor)
            try LocalSocket.writeAll(Data([0x0a]), to: descriptor)
        } catch {
            throw AutomaticControlControllerError.controllerUnavailable(socketPath: socketPath, reason: "failed to send request: \(error.localizedDescription)")
        }

        guard let line = try lineReader.readLine() else {
            throw AutomaticControlControllerError.controllerUnavailable(socketPath: socketPath, reason: "connection closed before a response was received")
        }

        let response: AutomaticControlControllerResponse
        do {
            response = try decoder.decode(AutomaticControlControllerResponse.self, from: Data(line.utf8))
        } catch {
            throw AutomaticControlControllerError.protocolViolation("failed to decode controller response: \(error.localizedDescription)")
        }

        guard response.ok else {
            switch response.errorCode {
            case "invalid_request":
                throw AutomaticControlControllerError.invalidRequest(response.errorMessage ?? "invalid controller request")
            default:
                throw AutomaticControlControllerError.controllerFailure(response.errorMessage ?? "controller request failed")
            }
        }

        guard let status = response.status else {
            throw AutomaticControlControllerError.protocolViolation("controller response was missing status")
        }
        return status
    }

    private func closeConnection() throws {
        guard !isClosed else {
            return
        }
        isClosed = true
        Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }
}

package struct AutomaticControlControllerLauncher {
    private let currentExecutablePath: String

    package init(currentExecutablePath: String) {
        self.currentExecutablePath = currentExecutablePath
    }

    package func ensureRunning() throws {
        if (try? AutomaticControlControllerClient.connect()) != nil {
            return
        }

        let executablePath = siblingControllerExecutablePath()
        guard FileManager.default.fileExists(atPath: executablePath) else {
            throw RuntimeCommandError("expected fan-control-controller next to current executable at \(executablePath); build the package first")
        }

        let logURL = URL(fileURLWithPath: AutomaticControlControllerPaths.logPath)
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.standardOutput = handle
        process.standardError = handle
        try process.run()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let client = try? AutomaticControlControllerClient.connect() {
                try? client.close()
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        throw RuntimeCommandError("fan-control-controller did not become ready at \(AutomaticControlControllerPaths.socketPath)")
    }

    private func siblingControllerExecutablePath() -> String {
        let currentURL = URL(fileURLWithPath: currentExecutablePath).resolvingSymlinksInPath()
        return currentURL.deletingLastPathComponent().appendingPathComponent("fan-control-controller").path
    }
}
