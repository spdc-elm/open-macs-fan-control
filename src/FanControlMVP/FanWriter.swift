import Foundation

protocol PrivilegedFanWriter {
    func inspectFans() throws -> [FanReading]
    func applyTarget(fanIndex: Int, rpm: Int) throws
    func restoreAutomaticMode(fanIndices: [Int]) throws
    func shutdown() throws
}

private struct WriterRequest: Codable {
    let command: String
    let fanIndex: Int?
    let rpm: Int?
    let fanIndices: [Int]?
}

private struct WriterResponse: Codable {
    let ok: Bool
    let error: String?
    let fans: [CodableFanReading]?
}

private struct CodableFanReading: Codable {
    let index: Int
    let currentRPM: Int
    let minimumRPM: Int
    let maximumRPM: Int
    let targetRPM: Int?
    let modeValue: Int?

    init(_ reading: FanReading) {
        index = reading.index
        currentRPM = reading.currentRPM
        minimumRPM = reading.minimumRPM
        maximumRPM = reading.maximumRPM
        targetRPM = reading.targetRPM
        modeValue = reading.modeValue
    }

    var asFanReading: FanReading {
        FanReading(
            index: index,
            currentRPM: currentRPM,
            minimumRPM: minimumRPM,
            maximumRPM: maximumRPM,
            targetRPM: targetRPM,
            modeValue: modeValue
        )
    }
}

final class HelperFanWriterClient: PrivilegedFanWriter {
    private let process: Process
    private let stdinPipe: Pipe
    private let stdoutReader: PipeLineReader
    private let stderrPipe: Pipe
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init(process: Process, stdinPipe: Pipe, stdoutReader: PipeLineReader, stderrPipe: Pipe) {
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutReader = stdoutReader
        self.stderrPipe = stderrPipe
    }

    static func launch(executablePath: String) throws -> HelperFanWriterClient {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let executableURL = URL(fileURLWithPath: executablePath)
        if geteuid() == 0 {
            process.executableURL = executableURL
            process.arguments = ["writer-service"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-n", executablePath, "writer-service"]
        }

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        return HelperFanWriterClient(
            process: process,
            stdinPipe: stdinPipe,
            stdoutReader: PipeLineReader(handle: stdoutPipe.fileHandleForReading),
            stderrPipe: stderrPipe
        )
    }

    func inspectFans() throws -> [FanReading] {
        let response = try send(.init(command: "inspectFans", fanIndex: nil, rpm: nil, fanIndices: nil))
        return (response.fans ?? []).map(\.asFanReading)
    }

    func applyTarget(fanIndex: Int, rpm: Int) throws {
        _ = try send(.init(command: "applyTarget", fanIndex: fanIndex, rpm: rpm, fanIndices: nil))
    }

    func restoreAutomaticMode(fanIndices: [Int]) throws {
        _ = try send(.init(command: "restoreAutomaticMode", fanIndex: nil, rpm: nil, fanIndices: fanIndices))
    }

    func shutdown() throws {
        guard process.isRunning else {
            return
        }

        _ = try? send(.init(command: "shutdown", fanIndex: nil, rpm: nil, fanIndices: nil))
        stdinPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()
    }

    private func send(_ request: WriterRequest) throws -> WriterResponse {
        guard process.isRunning else {
            let stderr = String(data: (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data(), encoding: .utf8) ?? ""
            throw AutomaticControlError.writer("writer process is not running. \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        let data = try encoder.encode(request)
        stdinPipe.fileHandleForWriting.write(data)
        stdinPipe.fileHandleForWriting.write(Data([0x0a]))

        guard let line = try stdoutReader.readLine() else {
            let stderr = String(data: (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data(), encoding: .utf8) ?? ""
            throw AutomaticControlError.writer("writer closed its response pipe unexpectedly. \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        let response = try decoder.decode(WriterResponse.self, from: Data(line.utf8))
        if response.ok {
            return response
        }

        throw AutomaticControlError.writer(response.error ?? "unknown writer failure")
    }
}

struct WriterServiceCommand {
    func run() throws {
        guard geteuid() == 0 else {
            throw CLIError("writer-service requires root privileges")
        }

        let connection = try SMCConnection.open()
        defer { connection.close() }

        let signalMonitor = SignalMonitor()
        defer { signalMonitor.stop() }

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var managedFans = Set<Int>()

        defer {
            for fanIndex in managedFans.sorted() {
                try? connection.restoreAutomaticMode(index: fanIndex)
            }
        }

        while !signalMonitor.terminationRequested, let line = readLine(strippingNewline: true) {
            let response: WriterResponse
            do {
                let request = try decoder.decode(WriterRequest.self, from: Data(line.utf8))
                response = try handle(request: request, connection: connection, managedFans: &managedFans)
            } catch {
                response = WriterResponse(ok: false, error: error.localizedDescription, fans: nil)
            }

            let data = try encoder.encode(response)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0a]))
        }
    }

    private func handle(
        request: WriterRequest,
        connection: SMCConnection,
        managedFans: inout Set<Int>
    ) throws -> WriterResponse {
        switch request.command {
        case "inspectFans":
            let fans = try connection.readFans().map(CodableFanReading.init)
            return WriterResponse(ok: true, error: nil, fans: fans)
        case "applyTarget":
            guard let fanIndex = request.fanIndex, let rpm = request.rpm else {
                throw AutomaticControlError.writer("applyTarget requires fanIndex and rpm")
            }
            if !managedFans.contains(fanIndex) {
                try connection.setFanManualMode(index: fanIndex)
                managedFans.insert(fanIndex)
            }
            try connection.setFanTargetRPM(index: fanIndex, rpm: rpm)
            return WriterResponse(ok: true, error: nil, fans: nil)
        case "restoreAutomaticMode":
            for fanIndex in request.fanIndices ?? [] {
                try connection.restoreAutomaticMode(index: fanIndex)
                managedFans.remove(fanIndex)
            }
            return WriterResponse(ok: true, error: nil, fans: nil)
        case "shutdown":
            for fanIndex in managedFans.sorted() {
                try connection.restoreAutomaticMode(index: fanIndex)
            }
            managedFans.removeAll()
            return WriterResponse(ok: true, error: nil, fans: nil)
        default:
            throw AutomaticControlError.writer("unknown writer command: \(request.command)")
        }
    }
}

final class PipeLineReader {
    private let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func readLine() throws -> String? {
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0a) {
                let lineData = buffer.prefix(upTo: newlineIndex)
                buffer.removeSubrange(...newlineIndex)
                return String(data: lineData, encoding: .utf8)
            }

            guard let chunk = try handle.read(upToCount: 1), !chunk.isEmpty else {
                if buffer.isEmpty {
                    return nil
                }
                defer { buffer.removeAll(keepingCapacity: true) }
                return String(data: buffer, encoding: .utf8)
            }

            buffer.append(chunk)
        }
    }
}
