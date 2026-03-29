import Foundation
import FanControlRuntime

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
        case "auto":
            return .automatic(try parseAutomatic(arguments.dropFirst(2)))
        case "daemon":
            return .daemon(try parseDaemon(arguments.dropFirst(2)))
        default:
            throw CLIError("unknown command: \(arguments[1])\n\n\(usage())")
        }
    }

    private func parseDaemon(_ args: ArraySlice<String>) throws -> DaemonCommandAction {
        guard let action = args.first else {
            throw CLIError("daemon requires one of: install, remove, status")
        }

        switch action {
        case "install":
            return .install
        case "remove":
            return .remove
        case "status":
            return .status
        default:
            throw CLIError("unknown daemon action: \(action)")
        }
    }

    private func parseAutomatic(_ args: ArraySlice<String>) throws -> AutomaticControlOptions {
        guard let actionToken = args.first else {
            throw CLIError("auto requires one of: start, stop, reload, status")
        }

        let action: AutomaticControlAction
        switch actionToken {
        case "start":
            action = .start
        case "stop":
            action = .stop
        case "reload":
            action = .reload
        case "status":
            action = .status
        default:
            // Keep the old shape as a compatibility alias for `auto start`.
            action = .start
        }

        var configPath: String?
        var dryRun = false

        let optionArgs = actionToken == "start" || actionToken == "stop" || actionToken == "reload" || actionToken == "status"
            ? args.dropFirst()
            : args

        var iterator = optionArgs.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--config":
                guard let value = iterator.next(), !value.isEmpty else {
                    throw CLIError("--config requires a file path")
                }
                configPath = value
            case "--dry-run":
                dryRun = true
            default:
                throw CLIError("unknown option for auto: \(arg)")
            }
        }

        if action == .start || action == .reload || dryRun {
            guard configPath != nil else {
                throw CLIError("auto \(action == .reload ? "reload" : "start") requires --config <path>")
            }
        }

        return AutomaticControlOptions(action: action, configPath: configPath, dryRun: dryRun)
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
        fan-control-cli: CLI surface over shared fan-control runtime

        Usage:
          fan-control-cli temps [--friendly|--raw]
          fan-control-cli fans
          fan-control-cli write --fan <index> --rpm <target> [--hold-seconds 10] [--verify-interval 1]
          fan-control-cli auto start --config <path> [--dry-run]
          fan-control-cli auto reload --config <path>
          fan-control-cli auto stop
          fan-control-cli auto status
          sudo fan-control-cli daemon <install|remove>
          fan-control-cli daemon status

        Commands:
          temps    Print temperature probes from the unified multi-source inventory
          fans     Print current fan RPM readings and fan metadata through the root writer daemon
          write    Attempt a manual fan RPM override through the root writer daemon, verify readback, then restore auto mode
          auto     Control the dedicated automatic-control controller service
          daemon   Install, remove, or inspect the root writer daemon lifecycle
        """
    }
}

enum Command {
    case temperatures(TemperatureOptions)
    case fans
    case write(WriteOptions)
    case automatic(AutomaticControlOptions)
    case daemon(DaemonCommandAction)

    func run() throws {
        switch self {
        case .temperatures(let options):
            try TemperatureProbe(options: options).run()
        case .fans:
            let writer = try DaemonFanWriterClient.connect()
            defer { try? writer.shutdown() }
            try FanProbe(writer: writer).run()
        case .write(let options):
            let writer = try DaemonFanWriterClient.connect()
            defer { try? writer.shutdown() }
            try FanWriteCommand(writer: writer, options: options).run()
        case .automatic(let options):
            try AutomaticControlCommand(options: options, currentExecutablePath: CommandLine.arguments[0]).run()
        case .daemon(let action):
            try DaemonLifecycleCommand(action: action, cliExecutablePath: CommandLine.arguments[0]).run()
        }
    }
}

enum DaemonCommandAction {
    case install
    case remove
    case status
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

struct DaemonLifecycleCommand {
    let action: DaemonCommandAction
    let cliExecutablePath: String

    func run() throws {
        let installer = RootWriterDaemonInstaller(cliExecutablePath: cliExecutablePath)

        switch action {
        case .install:
            try installer.install()
            print("installed root writer daemon")
            print("binary: \(RootWriterDaemonPaths.executablePath)")
            print("socket: \(RootWriterDaemonPaths.socketPath)")
        case .remove:
            try installer.remove()
            print("removed root writer daemon")
        case .status:
            let status = installer.status()
            print("# Root writer daemon status")
            print("binary=\(RootWriterDaemonPaths.executablePath) exists=\(status.installedBinaryExists)")
            print("launchdPlist=\(RootWriterDaemonPaths.launchDaemonPlistPath) exists=\(status.launchDaemonPlistExists)")
            print("socket=\(RootWriterDaemonPaths.socketPath) exists=\(status.socketExists)")
            print("connection=\(status.connectionMessage)")
        }
    }
}
