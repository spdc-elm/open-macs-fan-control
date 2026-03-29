import Foundation
import FanControlRuntime

struct AutomaticControlOptions {
    let configPath: String
    let dryRun: Bool
}

struct AutomaticControlCommand {
    let options: AutomaticControlOptions

    func run() throws {
        let inventory = TemperatureInventory.loadDefault()
        let writer = try DaemonFanWriterClient.connect()
        defer {
            try? writer.shutdown()
        }

        let bootstrap = AutomaticControlBootstrap(inventory: inventory, writer: writer)
        let config = try bootstrap.loadResolvedConfig(from: options.configPath)

        printResolvedConfiguration(config)
        if options.dryRun {
            print("dry-run complete; no fan overrides were issued")
            return
        }

        try runLoop(config: config, inventory: inventory, writer: writer)
    }

    private func runLoop(
        config: ResolvedAutomaticControlConfig,
        inventory: TemperatureInventory,
        writer: any PrivilegedFanWriter
    ) throws {
        print("starting automatic control; press Ctrl-C for handled shutdown")

        let signalMonitor = SignalMonitor()
        defer { signalMonitor.stop() }

        let resolver = AutomaticControlResolver(config: config)
        var fanStates = Dictionary(uniqueKeysWithValues: config.fans.map { ($0.fanIndex, FanControlState()) })
        var lastSuccessfulSampleAt = Date()

        do {
            while true {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                if signalMonitor.terminationRequested {
                    print("received handled termination signal; restoring automatic mode")
                    break
                }

                let readings = inventory.refreshAll()
                if let snapshot = try? resolver.resolveSnapshot(from: readings) {
                    lastSuccessfulSampleAt = Date()
                    try applyCycle(
                        config: config,
                        snapshot: snapshot,
                        resolver: resolver,
                        fanStates: &fanStates,
                        writer: writer
                    )
                } else if Date().timeIntervalSince(lastSuccessfulSampleAt) >= config.staleSensorTimeoutSeconds {
                    throw CLIError("required CPU/GPU domain sensor became stale")
                }

                Thread.sleep(forTimeInterval: config.pollingIntervalSeconds)
            }
        } catch {
            try? writer.restoreAutomaticMode(fanIndices: config.fans.map(\.fanIndex))
            throw error
        }

        try writer.restoreAutomaticMode(fanIndices: config.fans.map(\.fanIndex))
        print("restored automatic mode for managed fans")
    }

    private func applyCycle(
        config: ResolvedAutomaticControlConfig,
        snapshot: DomainSnapshot,
        resolver: AutomaticControlResolver,
        fanStates: inout [Int: FanControlState],
        writer: any PrivilegedFanWriter
    ) throws {
        let now = Date()

        for fan in config.fans {
            let plan = resolver.demandPlan(for: snapshot, fan: fan)
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

            print(
                "fan \(fan.fanIndex): cpu=\(plan.cpuDemandRPM)rpm gpu=\(plan.gpuDemandRPM)rpm target=\(plan.requestedTargetRPM)rpm applied=\(targetRPM)rpm"
            )
        }
    }

    private func printResolvedConfiguration(_ config: ResolvedAutomaticControlConfig) {
        print("# Automatic control initialization")
        print("config: \(config.sourcePath)")
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
}
