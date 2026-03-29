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

struct AutomaticControlConfig: Codable {
    let pollingIntervalSeconds: TimeInterval
    let minimumWriteIntervalSeconds: TimeInterval
    let staleSensorTimeoutSeconds: TimeInterval
    let smoothingStepRPM: Int
    let hysteresisRPM: Int
    let cpuDomain: ThermalDomainConfig
    let gpuDomain: ThermalDomainConfig
    let memoryDomain: ThermalDomainConfig?
    let fans: [FanPolicyConfig]
}

package struct ThermalDomainConfig: Codable {
    package let sensor: String
    package let startTemperatureCelsius: Double
    package let maxTemperatureCelsius: Double
}

struct FanPolicyConfig: Codable {
    let fanIndex: Int
    let minimumRPM: Int
    let maximumRPM: Int
}

package struct ResolvedAutomaticControlConfig {
    package let sourcePath: String
    package let pollingIntervalSeconds: TimeInterval
    package let minimumWriteIntervalSeconds: TimeInterval
    package let staleSensorTimeoutSeconds: TimeInterval
    package let smoothingStepRPM: Int
    package let hysteresisRPM: Int
    package let cpuDomain: ThermalDomainConfig
    package let gpuDomain: ThermalDomainConfig
    package let memoryDomain: ThermalDomainConfig?
    package let fans: [ResolvedFanPolicy]
}

package struct ResolvedFanPolicy {
    package let fanIndex: Int
    package let minimumRPM: Int
    package let maximumRPM: Int
    package let hardwareMinimumRPM: Int
    package let hardwareMaximumRPM: Int
}

package struct DomainSnapshot {
    package let cpuTemperatureCelsius: Double
    package let gpuTemperatureCelsius: Double
    package let memoryTemperatureCelsius: Double?
}

package struct FanDemandPlan: Equatable {
    package let cpuDemandRPM: Int
    package let gpuDemandRPM: Int
    package let memoryDemandRPM: Int?
    package let requestedTargetRPM: Int
}

package struct FanControlState {
    package var lastAppliedRPM: Int?
    package var lastWriteAt: Date?

    package init(lastAppliedRPM: Int? = nil, lastWriteAt: Date? = nil) {
        self.lastAppliedRPM = lastAppliedRPM
        self.lastWriteAt = lastWriteAt
    }

    package mutating func nextWriteTarget(
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

    package mutating func recordWrite(targetRPM: Int, at date: Date) {
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

package struct AutomaticControlResolver {
    package let config: ResolvedAutomaticControlConfig

    package init(config: ResolvedAutomaticControlConfig) {
        self.config = config
    }

    package func resolveSnapshot(from readings: [UnifiedTemperatureReading]) throws -> DomainSnapshot {
        let cpuReading = try resolveReading(named: config.cpuDomain.sensor, from: readings)
        let gpuReading = try resolveReading(named: config.gpuDomain.sensor, from: readings)

        var memoryTemperature: Double? = nil
        if let memoryDomain = config.memoryDomain {
            let memoryReading = try resolveReading(named: memoryDomain.sensor, from: readings)
            memoryTemperature = memoryReading.valueCelsius
        }

        return DomainSnapshot(
            cpuTemperatureCelsius: cpuReading.valueCelsius,
            gpuTemperatureCelsius: gpuReading.valueCelsius,
            memoryTemperatureCelsius: memoryTemperature
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

    package func demandPlan(for snapshot: DomainSnapshot, fan: ResolvedFanPolicy) -> FanDemandPlan {
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

        var memoryDemand: Int? = nil
        if let memoryDomain = config.memoryDomain, let memoryTemp = snapshot.memoryTemperatureCelsius {
            memoryDemand = DomainDemandCalculator.demandRPM(
                temperatureCelsius: memoryTemp,
                domain: memoryDomain,
                fan: fan
            )
        }

        var target = max(cpuDemand, gpuDemand)
        if let memoryDemand {
            target = max(target, memoryDemand)
        }

        return FanDemandPlan(
            cpuDemandRPM: cpuDemand,
            gpuDemandRPM: gpuDemand,
            memoryDemandRPM: memoryDemand,
            requestedTargetRPM: target
        )
    }
}

package struct AutomaticControlBootstrap {
    package let inventory: TemperatureInventory
    package let writer: any PrivilegedFanWriter

    package init(inventory: TemperatureInventory, writer: any PrivilegedFanWriter) {
        self.inventory = inventory
        self.writer = writer
    }

    package func loadResolvedConfig(from path: String) throws -> ResolvedAutomaticControlConfig {
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
        if let memoryDomain = config.memoryDomain {
            try validateDomain(memoryDomain, label: "memory")
        }

        let availableSensorNames = Set(inventory.refreshAll().map(\.rawName))
        guard availableSensorNames.contains(config.cpuDomain.sensor) else {
            throw AutomaticControlError.invalidConfig("cpuDomain.sensor references unknown sensor \(config.cpuDomain.sensor)")
        }
        guard availableSensorNames.contains(config.gpuDomain.sensor) else {
            throw AutomaticControlError.invalidConfig("gpuDomain.sensor references unknown sensor \(config.gpuDomain.sensor)")
        }
        if let memoryDomain = config.memoryDomain {
            guard availableSensorNames.contains(memoryDomain.sensor) else {
                throw AutomaticControlError.invalidConfig("memoryDomain.sensor references unknown sensor \(memoryDomain.sensor)")
            }
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
            memoryDomain: config.memoryDomain,
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
