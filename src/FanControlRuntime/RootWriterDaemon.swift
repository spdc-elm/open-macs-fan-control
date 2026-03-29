import Darwin
import Foundation

private func daemonLog(_ message: String) {
    let line = "[root-writer-daemon] \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
}

package enum RootWriterDaemonPaths {
    package static let installDirectory = "/usr/local/libexec/macs-fan-control"
    package static let executablePath = installDirectory + "/root-writer-daemon"
    package static let socketDirectory = "/var/run/macs-fan-control"
    package static let socketPath = socketDirectory + "/root-writer.sock"
    package static let launchDaemonLabel = "com.littlefairy.macs-fan-control.root-writer-daemon"
    package static let launchDaemonPlistPath = "/Library/LaunchDaemons/\(launchDaemonLabel).plist"
}

package protocol FanHardwareControlling: AnyObject {
    func readFans() throws -> [FanReading]
    func setFanManualMode(index: Int) throws
    func setFanTargetRPM(index: Int, rpm: Int) throws
    func restoreAutomaticMode(index: Int) throws
    func close()
}

private enum DaemonRequestError: LocalizedError {
    case conflict(fanIndex: Int)
    case invalidRequest(String)

    var errorDescription: String? {
        switch self {
        case .conflict(let fanIndex):
            return "fan \(fanIndex) is already owned by another live daemon session"
        case .invalidRequest(let message):
            return message
        }
    }
}

private struct SessionSnapshot {
    let managedFans: Set<Int>
}

private final class RootWriterDaemonState: @unchecked Sendable {
    private let lock = NSLock()
    private var nextSessionID = 1
    private var sessions: [Int: Set<Int>] = [:]
    private var fanOwners: [Int: Int] = [:]

    func makeSession() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let sessionID = nextSessionID
        nextSessionID += 1
        sessions[sessionID] = []
        return sessionID
    }

    func reserveFan(_ fanIndex: Int, for sessionID: Int) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if let owner = fanOwners[fanIndex], owner != sessionID {
            throw DaemonRequestError.conflict(fanIndex: fanIndex)
        }

        var managedFans = sessions[sessionID] ?? []
        let inserted = managedFans.insert(fanIndex).inserted
        sessions[sessionID] = managedFans
        fanOwners[fanIndex] = sessionID
        return inserted
    }

    func releaseFans(_ fanIndices: [Int], for sessionID: Int) -> [Int] {
        lock.lock()
        defer { lock.unlock() }

        guard var managedFans = sessions[sessionID] else {
            return []
        }

        var released: [Int] = []
        for fanIndex in fanIndices where fanOwners[fanIndex] == sessionID {
            fanOwners.removeValue(forKey: fanIndex)
            if managedFans.remove(fanIndex) != nil {
                released.append(fanIndex)
            }
        }
        sessions[sessionID] = managedFans
        return released
    }

    func releaseAll(for sessionID: Int) -> SessionSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let managedFans = sessions.removeValue(forKey: sessionID) ?? []
        for fanIndex in managedFans where fanOwners[fanIndex] == sessionID {
            fanOwners.removeValue(forKey: fanIndex)
        }
        return SessionSnapshot(managedFans: managedFans)
    }

    func releaseAllSessions() -> [Int] {
        lock.lock()
        defer { lock.unlock() }

        let fanIndices = Array(fanOwners.keys)
        fanOwners.removeAll()
        sessions.removeAll()
        return fanIndices
    }
}

package final class RootWriterDaemonServer: @unchecked Sendable {
    private let socketPath: String
    private let makeConnection: @Sendable () throws -> any FanHardwareControlling
    private let enforceRoot: Bool
    private let state = RootWriterDaemonState()
    private let lifecycleLock = NSLock()
    private var listenerDescriptor: Int32?
    private var shutdownRequested = false

    package init(
        socketPath: String = RootWriterDaemonPaths.socketPath,
        enforceRoot: Bool = true,
        makeConnection: @escaping @Sendable () throws -> any FanHardwareControlling = { try SMCConnection.open() }
    ) {
        self.socketPath = socketPath
        self.enforceRoot = enforceRoot
        self.makeConnection = makeConnection
    }

    package func run() throws {
        guard !enforceRoot || geteuid() == 0 else {
            throw RuntimeCommandError("root-writer-daemon requires root privileges")
        }

        signal(SIGPIPE, SIG_IGN)
        daemonLog("starting daemon at socket \(socketPath)")

        let fileManager = FileManager.default
        let socketDirectory = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        try fileManager.createDirectory(
            at: URL(fileURLWithPath: socketDirectory, isDirectory: true),
            withIntermediateDirectories: true
        )
        if chmod(socketDirectory, 0o755) != 0 {
            throw RuntimeCommandError("failed to set socket directory permissions at \(socketDirectory): \(String(cString: strerror(errno)))")
        }

        let listener = try LocalSocket.makeListener(path: socketPath)
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
        }

        let signalMonitor = SignalMonitor()
        defer { signalMonitor.stop() }

        while !signalMonitor.terminationRequested && !isShutdownRequested {
            let descriptor: Int32
            do {
                descriptor = try LocalSocket.accept(from: listener)
                daemonLog("accepted client connection")
            } catch {
                if signalMonitor.terminationRequested || isShutdownRequested {
                    break
                }
                daemonLog("accept failed: \(error.localizedDescription)")
                throw error
            }

            if isShutdownRequested {
                close(descriptor)
                break
            }

            let sessionID = state.makeSession()
            Thread.detachNewThread { [socketPath, state, makeConnection] in
                let server = SessionServer(
                    sessionID: sessionID,
                    descriptor: descriptor,
                    socketPath: socketPath,
                    state: state,
                    makeConnection: makeConnection
                )
                server.run()
            }
        }

        try cleanupOrphanedFans(state.releaseAllSessions())
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

    private func cleanupOrphanedFans(_ fanIndices: [Int]) throws {
        guard !fanIndices.isEmpty else {
            return
        }

        let connection = try makeConnection()
        defer { connection.close() }
        for fanIndex in fanIndices.sorted() {
            try? connection.restoreAutomaticMode(index: fanIndex)
        }
    }

    private var isShutdownRequested: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return shutdownRequested
    }
}

private final class SessionServer {
    private let sessionID: Int
    private let socketPath: String
    private let state: RootWriterDaemonState
    private let makeConnection: @Sendable () throws -> any FanHardwareControlling
    private let descriptor: Int32
    private let lineReader: PipeLineReader
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        sessionID: Int,
        descriptor: Int32,
        socketPath: String,
        state: RootWriterDaemonState,
        makeConnection: @escaping @Sendable () throws -> any FanHardwareControlling
    ) {
        self.sessionID = sessionID
        self.socketPath = socketPath
        self.state = state
        self.makeConnection = makeConnection
        self.descriptor = descriptor
        self.lineReader = PipeLineReader(descriptor: descriptor)
    }

    func run() {
        let connection: any FanHardwareControlling
        do {
            daemonLog("session \(sessionID): opening hardware connection")
            connection = try makeConnection()
            daemonLog("session \(sessionID): hardware connection ready")
        } catch {
            daemonLog("session \(sessionID): failed to open hardware connection: \(error.localizedDescription)")
            try? send(.failure(code: "daemon_failure", message: error.localizedDescription))
            cleanup(connection: nil)
            return
        }
        defer { cleanup(connection: connection) }

        while true {
            guard let line = try? lineReader.readLine() else {
                break
            }
            let response: WriterResponse
            var shouldClose = false

            do {
                let request = try decoder.decode(WriterRequest.self, from: Data(line.utf8))
                daemonLog("session \(sessionID): handling \(request.command.rawValue)")
                let handled = try handle(request: request, connection: connection)
                response = handled.response
                shouldClose = handled.shouldClose
            } catch let error as DaemonRequestError {
                daemonLog("session \(sessionID): request error: \(error.localizedDescription)")
                switch error {
                case .conflict(let fanIndex):
                    response = .failure(code: "conflict", message: "fan \(fanIndex) is already owned by another live daemon session")
                case .invalidRequest(let message):
                    response = .failure(code: "invalid_request", message: message)
                }
            } catch {
                daemonLog("session \(sessionID): unexpected error: \(error.localizedDescription)")
                response = .failure(code: "daemon_failure", message: error.localizedDescription)
            }

            do {
                try send(response)
                daemonLog("session \(sessionID): response sent")
            } catch {
                daemonLog("session \(sessionID): failed to send response: \(error.localizedDescription)")
                break
            }

            if shouldClose {
                break
            }
        }
    }

    private func handle(request: WriterRequest, connection: any FanHardwareControlling) throws -> (response: WriterResponse, shouldClose: Bool) {
        switch request.command {
        case .inspectFans:
            return (.success(fans: try connection.readFans()), false)
        case .applyTarget:
            guard let fanIndex = request.fanIndex, let rpm = request.rpm else {
                throw DaemonRequestError.invalidRequest("applyTarget requires fanIndex and rpm")
            }

            if try state.reserveFan(fanIndex, for: sessionID) {
                try connection.setFanManualMode(index: fanIndex)
            }
            try connection.setFanTargetRPM(index: fanIndex, rpm: rpm)
            return (.success(), false)
        case .restoreAutomaticMode:
            let released = state.releaseFans(request.fanIndices ?? [], for: sessionID)
            for fanIndex in released.sorted() {
                try connection.restoreAutomaticMode(index: fanIndex)
            }
            return (.success(), false)
        case .shutdown:
            let snapshot = state.releaseAll(for: sessionID)
            for fanIndex in snapshot.managedFans.sorted() {
                try? connection.restoreAutomaticMode(index: fanIndex)
            }
            return (.success(), true)
        }
    }

    private func send(_ response: WriterResponse) throws {
        let data = try encoder.encode(response)
        try LocalSocket.writeAll(data, to: descriptor)
        try LocalSocket.writeAll(Data([0x0a]), to: descriptor)
    }

    private func cleanup(connection: (any FanHardwareControlling)?) {
        daemonLog("session \(sessionID): cleaning up")
        let snapshot = state.releaseAll(for: sessionID)
        if let connection {
            for fanIndex in snapshot.managedFans.sorted() {
                try? connection.restoreAutomaticMode(index: fanIndex)
            }
            connection.close()
        }

        Darwin.shutdown(descriptor, SHUT_RDWR)
        close(descriptor)
        _ = socketPath
    }
}

package struct RootWriterDaemonCommand {
    package init() {}

    package func run() throws {
        try RootWriterDaemonServer().run()
    }
}
