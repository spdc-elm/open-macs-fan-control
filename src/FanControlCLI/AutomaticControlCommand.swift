import Foundation
import FanControlRuntime

enum AutomaticControlAction {
    case start
    case stop
    case reload
    case status
}

struct AutomaticControlOptions {
    let action: AutomaticControlAction
    let configPath: String?
    let dryRun: Bool
}

struct AutomaticControlCommand {
    let options: AutomaticControlOptions
    let currentExecutablePath: String

    func run() throws {
        if options.dryRun {
            try runDryRun()
            return
        }

        switch options.action {
        case .start:
            try AutomaticControlControllerLauncher(currentExecutablePath: currentExecutablePath).ensureRunning()
            let client = try AutomaticControlControllerClient.connect()
            defer { try? client.close() }
            let status = try client.start(configPath: requiredConfigPath(action: "start"))
            printStatus(status, headline: "# Automatic control controller started")
        case .reload:
            let client = try AutomaticControlControllerClient.connect()
            defer { try? client.close() }
            let status = try client.reload(configPath: requiredConfigPath(action: "reload"))
            printStatus(status, headline: "# Automatic control controller reloaded")
        case .stop:
            let client = try AutomaticControlControllerClient.connect()
            defer { try? client.close() }
            let status = try client.stop()
            printStatus(status, headline: "# Automatic control controller stopped")
        case .status:
            let client = try AutomaticControlControllerClient.connect()
            defer { try? client.close() }
            let status = try client.status()
            printStatus(status, headline: "# Automatic control controller status")
        }
    }

    private func runDryRun() throws {
        let inventory = TemperatureInventory.loadDefault()
        let writer = try DaemonFanWriterClient.connect()
        defer { try? writer.shutdown() }

        let bootstrap = AutomaticControlBootstrap(inventory: inventory, writer: writer)
        let config = try bootstrap.loadResolvedConfig(from: requiredConfigPath(action: "dry-run"))
        printResolvedConfiguration(config)
        print("dry-run complete; controller validation succeeded and no fan overrides were issued")
    }

    private func requiredConfigPath(action: String) throws -> String {
        guard let configPath = options.configPath, !configPath.isEmpty else {
            throw CLIError("auto \(action) requires --config <path>")
        }
        return configPath
    }

    private func printResolvedConfiguration(_ config: ResolvedAutomaticControlConfig) {
        print("# Automatic control validation")
        print("config: \(config.sourcePath)")
        print("controllerSocket=\(AutomaticControlControllerPaths.socketPath)")
        print("writerDaemonSocket=\(RootWriterDaemonPaths.socketPath)")
        print("pollingIntervalSeconds=\(config.pollingIntervalSeconds) minimumWriteIntervalSeconds=\(config.minimumWriteIntervalSeconds) staleSensorTimeoutSeconds=\(config.staleSensorTimeoutSeconds)")
        print("smoothingStepRPM=\(config.smoothingStepRPM) hysteresisRPM=\(config.hysteresisRPM)")
        print("cpuDomain: sensor=\(config.cpuDomain.sensor) start=\(config.cpuDomain.startTemperatureCelsius)C max=\(config.cpuDomain.maxTemperatureCelsius)C")
        print("gpuDomain: sensor=\(config.gpuDomain.sensor) start=\(config.gpuDomain.startTemperatureCelsius)C max=\(config.gpuDomain.maxTemperatureCelsius)C")
        for fan in config.fans {
            print(
                "fan \(fan.fanIndex): policyMin=\(fan.minimumRPM) policyMax=\(fan.maximumRPM) hardwareMin=\(fan.hardwareMinimumRPM) hardwareMax=\(fan.hardwareMaximumRPM)"
            )
        }
    }

    private func printStatus(_ status: AutomaticControlStatusSnapshot, headline: String) {
        print(headline)
        print("controllerSocket=\(AutomaticControlControllerPaths.socketPath)")
        print("phase=\(status.phase.rawValue)")
        print("activeConfig=\(status.activeConfigPath ?? "none")")
        print("writerConnected=\(status.writerConnected)")

        if let lastSampleAt = status.lastSampleAt {
            print("lastSampleAt=\(iso8601(lastSampleAt))")
        }
        if let lastSuccessfulSampleAt = status.lastSuccessfulSampleAt {
            print("lastSuccessfulSampleAt=\(iso8601(lastSuccessfulSampleAt))")
        }
        if let lastError = status.lastError {
            print("lastError=\(lastError)")
        }

        if status.fans.isEmpty {
            print("managedFans=none")
            return
        }

        for fan in status.fans {
            let requested = fan.lastRequestedRPM.map(String.init) ?? "n/a"
            let applied = fan.lastAppliedRPM.map(String.init) ?? "n/a"
            let lastWrite = fan.lastWriteAt.map(iso8601) ?? "n/a"
            print("fan \(fan.fanIndex): requested=\(requested)rpm applied=\(applied)rpm lastWriteAt=\(lastWrite)")
        }
    }

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
