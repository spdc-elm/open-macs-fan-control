import Foundation

enum AutomaticControlError: LocalizedError {
    case invalidConfig(String)
    case unavailableSensor(String)
    case ambiguousSensor(String, Int)
    case unavailableFan(Int)
    case writer(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfig(let message):
            return "invalid automatic-control config: \(message)"
        case .unavailableSensor(let sensor):
            return "configured sensor is unavailable: \(sensor)"
        case .ambiguousSensor(let sensor, let count):
            return "configured sensor \(sensor) is ambiguous because \(count) readings share that raw name"
        case .unavailableFan(let index):
            return "configured fan \(index) is unavailable"
        case .writer(let message):
            return "writer error: \(message)"
        }
    }
}

struct AutomaticControlOptions {
    let configPath: String
    let dryRun: Bool
}

struct AutomaticControlConfig: Codable {
    let pollingIntervalSeconds: TimeInterval
    let minimumWriteIntervalSeconds: TimeInterval
    let staleSensorTimeoutSeconds: TimeInterval
    let smoothingStepRPM: Int
    let hysteresisRPM: Int
    let cpuDomain: ThermalDomainConfig
    let gpuDomain: ThermalDomainConfig
    let fans: [FanPolicyConfig]
}

struct ThermalDomainConfig: Codable {
    let sensor: String
    let startTemperatureCelsius: Double
    let maxTemperatureCelsius: Double
}

struct FanPolicyConfig: Codable {
    let fanIndex: Int
    let minimumRPM: Int
    let maximumRPM: Int
}

struct ResolvedAutomaticControlConfig {
    let sourcePath: String
    let pollingIntervalSeconds: TimeInterval
    let minimumWriteIntervalSeconds: TimeInterval
    let staleSensorTimeoutSeconds: TimeInterval
    let smoothingStepRPM: Int
    let hysteresisRPM: Int
    let cpuDomain: ThermalDomainConfig
    let gpuDomain: ThermalDomainConfig
    let fans: [ResolvedFanPolicy]
}

struct ResolvedFanPolicy {
    let fanIndex: Int
    let minimumRPM: Int
    let maximumRPM: Int
    let hardwareMinimumRPM: Int
    let hardwareMaximumRPM: Int
}

struct DomainSnapshot {
    let cpuTemperatureCelsius: Double
    let gpuTemperatureCelsius: Double
}

struct FanDemandPlan: Equatable {
    let cpuDemandRPM: Int
    let gpuDemandRPM: Int
    let requestedTargetRPM: Int
}

struct FanControlState {
    var lastAppliedRPM: Int?
    var lastWriteAt: Date?

    mutating func nextWriteTarget(
        requestedRPM: Int,
        now: Date,
        smoothingStepRPM: Int,
        hysteresisRPM: Int,
        minimumWriteInterval: TimeInterval
    ) -> Int? {
        let candidate: Int
        if let lastAppliedRPM {
            let delta = requestedRPM - lastAppliedRPM
            if abs(delta) <= hysteresisRPM {
                return nil
            }

            let step = min(abs(delta), smoothingStepRPM)
            candidate = lastAppliedRPM + (delta.signum() * step)
        } else {
            candidate = requestedRPM
        }

        if let lastWriteAt, now.timeIntervalSince(lastWriteAt) < minimumWriteInterval {
            return nil
        }

        if let lastAppliedRPM, abs(candidate - lastAppliedRPM) < hysteresisRPM {
            return nil
        }

        return candidate
    }

    mutating func recordWrite(targetRPM: Int, at date: Date) {
        lastAppliedRPM = targetRPM
        lastWriteAt = date
    }
}

enum DomainDemandCalculator {
    static func demandRPM(
        temperatureCelsius: Double,
        domain: ThermalDomainConfig,
        fan: ResolvedFanPolicy
    ) -> Int {
        let start = domain.startTemperatureCelsius
        let max = domain.maxTemperatureCelsius

        if temperatureCelsius <= start {
            return fan.minimumRPM
        }

        if temperatureCelsius >= max {
            return fan.maximumRPM
        }

        let normalized = (temperatureCelsius - start) / (max - start)
        let span = Double(fan.maximumRPM - fan.minimumRPM)
        let rpm = Double(fan.minimumRPM) + (normalized * span)
        return Int(rpm.rounded())
    }
}

struct AutomaticControlResolver {
    let config: ResolvedAutomaticControlConfig

    func resolveSnapshot(from readings: [UnifiedTemperatureReading]) throws -> DomainSnapshot {
        let cpuReading = try resolveReading(named: config.cpuDomain.sensor, from: readings)
        let gpuReading = try resolveReading(named: config.gpuDomain.sensor, from: readings)

        return DomainSnapshot(
            cpuTemperatureCelsius: cpuReading.valueCelsius,
            gpuTemperatureCelsius: gpuReading.valueCelsius
        )
    }

    private func resolveReading(named rawName: String, from readings: [UnifiedTemperatureReading]) throws -> UnifiedTemperatureReading {
        let matches = readings.filter { $0.rawName == rawName }
        guard !matches.isEmpty else {
            throw AutomaticControlError.unavailableSensor(rawName)
        }
        guard matches.count == 1 else {
            throw AutomaticControlError.ambiguousSensor(rawName, matches.count)
        }
        return matches[0]
    }

    func demandPlan(for snapshot: DomainSnapshot, fan: ResolvedFanPolicy) -> FanDemandPlan {
        let cpuDemand = DomainDemandCalculator.demandRPM(
            temperatureCelsius: snapshot.cpuTemperatureCelsius,
            domain: config.cpuDomain,
            fan: fan
        )
        let gpuDemand = DomainDemandCalculator.demandRPM(
            temperatureCelsius: snapshot.gpuTemperatureCelsius,
            domain: config.gpuDomain,
            fan: fan
        )

        return FanDemandPlan(
            cpuDemandRPM: cpuDemand,
            gpuDemandRPM: gpuDemand,
            requestedTargetRPM: max(cpuDemand, gpuDemand)
        )
    }
}

struct AutomaticControlBootstrap {
    let inventory: TemperatureInventory
    let writer: any PrivilegedFanWriter

    func loadResolvedConfig(from path: String) throws -> ResolvedAutomaticControlConfig {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        let rawConfig = try decoder.decode(AutomaticControlConfig.self, from: data)
        return try resolve(config: rawConfig, sourcePath: path)
    }

    private func resolve(config: AutomaticControlConfig, sourcePath: String) throws -> ResolvedAutomaticControlConfig {
        guard config.pollingIntervalSeconds > 0 else {
            throw AutomaticControlError.invalidConfig("pollingIntervalSeconds must be > 0")
        }
        guard config.minimumWriteIntervalSeconds > 0 else {
            throw AutomaticControlError.invalidConfig("minimumWriteIntervalSeconds must be > 0")
        }
        guard config.staleSensorTimeoutSeconds >= config.pollingIntervalSeconds else {
            throw AutomaticControlError.invalidConfig("staleSensorTimeoutSeconds must be >= pollingIntervalSeconds")
        }
        guard config.smoothingStepRPM > 0 else {
            throw AutomaticControlError.invalidConfig("smoothingStepRPM must be > 0")
        }
        guard config.hysteresisRPM >= 0 else {
            throw AutomaticControlError.invalidConfig("hysteresisRPM must be >= 0")
        }
        guard !config.fans.isEmpty else {
            throw AutomaticControlError.invalidConfig("at least one fan policy is required")
        }

        try validateDomain(config.cpuDomain, label: "cpu")
        try validateDomain(config.gpuDomain, label: "gpu")

        let availableSensorNames = Set(inventory.refreshAll().map(\.rawName))
        guard availableSensorNames.contains(config.cpuDomain.sensor) else {
            throw AutomaticControlError.invalidConfig("cpuDomain.sensor references unknown sensor \(config.cpuDomain.sensor)")
        }
        guard availableSensorNames.contains(config.gpuDomain.sensor) else {
            throw AutomaticControlError.invalidConfig("gpuDomain.sensor references unknown sensor \(config.gpuDomain.sensor)")
        }

        let fanInventory = Dictionary(uniqueKeysWithValues: try writer.inspectFans().map { ($0.index, $0) })
        var seenFanIndices = Set<Int>()
        let resolvedFans = try config.fans.map { fan in
            guard seenFanIndices.insert(fan.fanIndex).inserted else {
                throw AutomaticControlError.invalidConfig("fan \(fan.fanIndex) is listed more than once")
            }
            guard let hardwareFan = fanInventory[fan.fanIndex] else {
                throw AutomaticControlError.invalidConfig("fan \(fan.fanIndex) does not exist on this machine")
            }
            guard fan.minimumRPM > 0 else {
                throw AutomaticControlError.invalidConfig("fan \(fan.fanIndex) minimumRPM must be > 0")
            }
            guard fan.maximumRPM >= fan.minimumRPM else {
                throw AutomaticControlError.invalidConfig("fan \(fan.fanIndex) maximumRPM must be >= minimumRPM")
            }
            guard fan.minimumRPM >= hardwareFan.minimumRPM else {
                throw AutomaticControlError.invalidConfig("fan \(fan.fanIndex) minimumRPM \(fan.minimumRPM) is below hardware minimum \(hardwareFan.minimumRPM)")
            }
            guard fan.maximumRPM <= hardwareFan.maximumRPM else {
                throw AutomaticControlError.invalidConfig("fan \(fan.fanIndex) maximumRPM \(fan.maximumRPM) exceeds hardware maximum \(hardwareFan.maximumRPM)")
            }

            return ResolvedFanPolicy(
                fanIndex: fan.fanIndex,
                minimumRPM: fan.minimumRPM,
                maximumRPM: fan.maximumRPM,
                hardwareMinimumRPM: hardwareFan.minimumRPM,
                hardwareMaximumRPM: hardwareFan.maximumRPM
            )
        }

        return ResolvedAutomaticControlConfig(
            sourcePath: sourcePath,
            pollingIntervalSeconds: config.pollingIntervalSeconds,
            minimumWriteIntervalSeconds: config.minimumWriteIntervalSeconds,
            staleSensorTimeoutSeconds: config.staleSensorTimeoutSeconds,
            smoothingStepRPM: config.smoothingStepRPM,
            hysteresisRPM: config.hysteresisRPM,
            cpuDomain: config.cpuDomain,
            gpuDomain: config.gpuDomain,
            fans: resolvedFans
        )
    }

    private func validateDomain(_ domain: ThermalDomainConfig, label: String) throws {
        guard !domain.sensor.isEmpty else {
            throw AutomaticControlError.invalidConfig("\(label)Domain.sensor is required")
        }
        guard domain.startTemperatureCelsius >= 0 else {
            throw AutomaticControlError.invalidConfig("\(label)Domain.startTemperatureCelsius must be >= 0")
        }
        guard domain.maxTemperatureCelsius > domain.startTemperatureCelsius else {
            throw AutomaticControlError.invalidConfig("\(label)Domain.maxTemperatureCelsius must be > startTemperatureCelsius")
        }
    }
}

struct AutomaticControlCommand {
    let options: AutomaticControlOptions

    func run() throws {
        let inventory = TemperatureInventory.loadDefault()
        let writer = try HelperFanWriterClient.launch(executablePath: CommandLine.arguments[0])
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
                    throw AutomaticControlError.unavailableSensor("required CPU/GPU domain sensor became stale")
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
