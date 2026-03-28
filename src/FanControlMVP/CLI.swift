import Foundation

struct CLI {
    let arguments: [String]

    func parse() throws -> Command {
        guard arguments.count >= 2 else {
            throw CLIError(usage())
        }

        switch arguments[1] {
        case "help", "--help", "-h":
            throw CLIError(usage(), exitCode: 0)
        case "temps":
            return .temperatures(try parseTemperatureOptions(arguments.dropFirst(2)))
        case "fans":
            return .fans
        case "write":
            return .write(try parseWrite(arguments.dropFirst(2)))
        default:
            throw CLIError("unknown command: \(arguments[1])\n\n\(usage())")
        }
    }

    private func parseWrite(_ args: ArraySlice<String>) throws -> WriteOptions {
        var fanIndex: Int?
        var rpm: Int?
        var holdSeconds: TimeInterval = 10
        var verifyInterval: TimeInterval = 1

        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--fan":
                guard let value = iterator.next(), let parsed = Int(value) else {
                    throw CLIError("--fan requires an integer value")
                }
                fanIndex = parsed
            case "--rpm":
                guard let value = iterator.next(), let parsed = Int(value) else {
                    throw CLIError("--rpm requires an integer value")
                }
                rpm = parsed
            case "--hold-seconds":
                guard let value = iterator.next(), let parsed = TimeInterval(value) else {
                    throw CLIError("--hold-seconds requires a numeric value")
                }
                holdSeconds = parsed
            case "--verify-interval":
                guard let value = iterator.next(), let parsed = TimeInterval(value) else {
                    throw CLIError("--verify-interval requires a numeric value")
                }
                verifyInterval = parsed
            default:
                throw CLIError("unknown option for write: \(arg)")
            }
        }

        guard let fanIndex else {
            throw CLIError("write requires --fan <index>")
        }
        guard let rpm else {
            throw CLIError("write requires --rpm <target>")
        }
        guard holdSeconds > 0 else {
            throw CLIError("--hold-seconds must be > 0")
        }
        guard verifyInterval > 0 else {
            throw CLIError("--verify-interval must be > 0")
        }

        return WriteOptions(
            fanIndex: fanIndex,
            rpm: rpm,
            holdSeconds: holdSeconds,
            verifyInterval: verifyInterval
        )
    }

    private func parseTemperatureOptions(_ args: ArraySlice<String>) throws -> TemperatureOptions {
        var format: TemperatureOutputFormat = .raw

        for arg in args {
            switch arg {
            case "--friendly":
                format = .friendly
            case "--raw":
                format = .raw
            default:
                throw CLIError("unknown option for temps: \(arg)")
            }
        }

        return TemperatureOptions(format: format)
    }

    private func usage() -> String {
        """
        fancontrol-mvp: terminal-first hardware validation tool

        Usage:
          fancontrol-mvp temps [--friendly|--raw]
          fancontrol-mvp fans
          sudo fancontrol-mvp write --fan <index> --rpm <target> [--hold-seconds 10] [--verify-interval 1]

        Commands:
          temps    Print temperature probes from the unified multi-source inventory
          fans     Print current fan RPM readings and fan metadata
          write    Attempt a manual fan RPM override, verify readback, then restore auto mode
        """
    }
}

enum Command {
    case temperatures(TemperatureOptions)
    case fans
    case write(WriteOptions)

    func run() throws {
        switch self {
        case .temperatures(let options):
            try TemperatureProbe(options: options).run()
        case .fans:
            let smc = try SMCConnection.open()
            defer { smc.close() }
            try FanProbe(connection: smc).run()
        case .write(let options):
            let smc = try SMCConnection.open()
            defer { smc.close() }
            try FanWriteCommand(connection: smc, options: options).run()
        }
    }
}

struct TemperatureOptions {
    let format: TemperatureOutputFormat
}

enum TemperatureOutputFormat {
    case raw
    case friendly
}

struct WriteOptions {
    let fanIndex: Int
    let rpm: Int
    let holdSeconds: TimeInterval
    let verifyInterval: TimeInterval
}

struct CLIError: Error {
    let message: String
    let exitCode: Int32

    init(_ message: String, exitCode: Int32 = 2) {
        self.message = message
        self.exitCode = exitCode
    }
}
