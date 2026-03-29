import Foundation

package protocol PrivilegedFanWriter {
    func inspectFans() throws -> [FanReading]
    func applyTarget(fanIndex: Int, rpm: Int) throws
    func restoreAutomaticMode(fanIndices: [Int]) throws
    func shutdown() throws
}

package enum FanWriterError: LocalizedError, Equatable {
    case daemonUnavailable(socketPath: String, reason: String)
    case conflict(fanIndex: Int)
    case invalidRequest(String)
    case protocolViolation(String)
    case daemonFailure(String)

    package var errorDescription: String? {
        switch self {
        case .daemonUnavailable(let socketPath, let reason):
            return "root writer daemon is unavailable at \(socketPath): \(reason). install/start it with `fan-control-cli daemon install`"
        case .conflict(let fanIndex):
            return "fan \(fanIndex) is already owned by another live daemon session"
        case .invalidRequest(let message):
            return "invalid daemon request: \(message)"
        case .protocolViolation(let message):
            return "daemon protocol error: \(message)"
        case .daemonFailure(let message):
            return "root writer daemon error: \(message)"
        }
    }
}

package enum WriterCommand: String, Codable {
    case inspectFans
    case applyTarget
    case restoreAutomaticMode
    case shutdown
}

package struct WriterRequest: Codable {
    package let command: WriterCommand
    package let fanIndex: Int?
    package let rpm: Int?
    package let fanIndices: [Int]?

    package init(command: WriterCommand, fanIndex: Int? = nil, rpm: Int? = nil, fanIndices: [Int]? = nil) {
        self.command = command
        self.fanIndex = fanIndex
        self.rpm = rpm
        self.fanIndices = fanIndices
    }
}

package struct WriterResponse: Codable {
    package let ok: Bool
    package let errorCode: String?
    package let errorMessage: String?
    package let fans: [CodableFanReading]?

    package static func success(fans: [FanReading]? = nil) -> WriterResponse {
        WriterResponse(
            ok: true,
            errorCode: nil,
            errorMessage: nil,
            fans: fans?.map(CodableFanReading.init)
        )
    }

    package static func failure(code: String, message: String) -> WriterResponse {
        WriterResponse(
            ok: false,
            errorCode: code,
            errorMessage: message,
            fans: nil
        )
    }
}

package struct CodableFanReading: Codable {
    package let index: Int
    package let currentRPM: Int
    package let minimumRPM: Int
    package let maximumRPM: Int
    package let targetRPM: Int?
    package let modeValue: Int?

    package init(_ reading: FanReading) {
        index = reading.index
        currentRPM = reading.currentRPM
        minimumRPM = reading.minimumRPM
        maximumRPM = reading.maximumRPM
        targetRPM = reading.targetRPM
        modeValue = reading.modeValue
    }

    package var asFanReading: FanReading {
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

package final class DaemonFanWriterClient: PrivilegedFanWriter {
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

    package static func connect(socketPath: String = RootWriterDaemonPaths.socketPath) throws -> DaemonFanWriterClient {
        let descriptor: Int32
        do {
            descriptor = try LocalSocket.connect(to: socketPath)
        } catch let error as FanWriterError {
            throw error
        } catch {
            throw FanWriterError.daemonUnavailable(socketPath: socketPath, reason: error.localizedDescription)
        }

        return DaemonFanWriterClient(socketPath: socketPath, descriptor: descriptor)
    }

    package func inspectFans() throws -> [FanReading] {
        let response = try send(.init(command: .inspectFans))
        return (response.fans ?? []).map(\.asFanReading)
    }

    package func applyTarget(fanIndex: Int, rpm: Int) throws {
        _ = try send(.init(command: .applyTarget, fanIndex: fanIndex, rpm: rpm))
    }

    package func restoreAutomaticMode(fanIndices: [Int]) throws {
        _ = try send(.init(command: .restoreAutomaticMode, fanIndices: fanIndices))
    }

    package func shutdown() throws {
        guard !isClosed else {
            return
        }

        _ = try? send(.init(command: .shutdown))
        try closeConnection()
    }

    private func send(_ request: WriterRequest) throws -> WriterResponse {
        guard !isClosed else {
            throw FanWriterError.daemonUnavailable(socketPath: socketPath, reason: "client session is already closed")
        }

        do {
            let data = try encoder.encode(request)
            try LocalSocket.writeAll(data, to: descriptor)
            try LocalSocket.writeAll(Data([0x0a]), to: descriptor)
        } catch {
            throw FanWriterError.daemonUnavailable(socketPath: socketPath, reason: "failed to send request: \(error.localizedDescription)")
        }

        guard let line = try lineReader.readLine() else {
            throw FanWriterError.daemonUnavailable(socketPath: socketPath, reason: "connection closed before a response was received")
        }

        let response: WriterResponse
        do {
            response = try decoder.decode(WriterResponse.self, from: Data(line.utf8))
        } catch {
            throw FanWriterError.protocolViolation("failed to decode daemon response: \(error.localizedDescription)")
        }

        guard response.ok else {
            throw Self.mapError(from: response)
        }
        return response
    }

    private func closeConnection() throws {
        guard !isClosed else {
            return
        }

        isClosed = true
        Darwin.shutdown(descriptor, SHUT_RDWR)
        close(descriptor)
    }

    private static func mapError(from response: WriterResponse) -> Error {
        switch response.errorCode {
        case "conflict":
            let fanIndex = response.errorMessage?
                .split(separator: " ")
                .compactMap { Int($0) }
                .first ?? -1
            return FanWriterError.conflict(fanIndex: fanIndex)
        case "invalid_request":
            return FanWriterError.invalidRequest(response.errorMessage ?? "unknown request failure")
        case "protocol":
            return FanWriterError.protocolViolation(response.errorMessage ?? "unknown protocol failure")
        default:
            return FanWriterError.daemonFailure(response.errorMessage ?? "unknown daemon failure")
        }
    }
}

package struct RuntimeCommandError: LocalizedError {
    package let message: String

    package init(_ message: String) {
        self.message = message
    }

    package var errorDescription: String? {
        message
    }
}

package final class PipeLineReader {
    private let descriptor: Int32
    private var buffer = Data()

    package init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    package func readLine() throws -> String? {
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0a) {
                let lineData = buffer.prefix(upTo: newlineIndex)
                buffer.removeSubrange(...newlineIndex)
                return String(data: lineData, encoding: .utf8)
            }

            let chunk = try LocalSocket.readChunk(from: descriptor, maxBytes: 4096)
            if chunk.isEmpty {
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
