import Foundation
import IOKit

enum TemperatureSource: String {
    case iohid = "IOHID"
    case smc = "SMC"
    case gpu = "GPU"
    case disk = "Disk"
    case aggregate = "Aggregate"
}

struct UnifiedTemperatureReading {
    let source: TemperatureSource
    let rawName: String
    let displayName: String
    let valueCelsius: Double
    let group: String?
    let type: String?
    let sortKey: String
}

protocol TemperatureSensor {
    var source: TemperatureSource { get }
    var rawName: String { get }
    var displayName: String { get }
    var group: String? { get }
    var type: String? { get }
    var sortKey: String { get }

    func refreshValue() -> Double?
}

protocol TemperatureSensorProvider {
    func loadSensors() -> [any TemperatureSensor]
}

final class TemperatureRuntime {
    lazy var smcConnection: SMCConnection? = try? SMCConnection.open()

    deinit {
        smcConnection?.close()
    }
}

struct TemperatureInventory {
    let runtime: TemperatureRuntime
    let sensors: [any TemperatureSensor]

    static func loadDefault() -> TemperatureInventory {
        let runtime = TemperatureRuntime()
        let providers: [any TemperatureSensorProvider] = [
            IOHIDTemperatureProvider(),
            SMCTemperatureProvider(runtime: runtime),
            GPUTemperatureProvider(runtime: runtime),
            DiskTemperatureProvider()
        ]

        return TemperatureInventory(
            runtime: runtime,
            sensors: providers.flatMap { $0.loadSensors() }
        )
    }

    func refreshAll() -> [UnifiedTemperatureReading] {
        var baseReadings: [UnifiedTemperatureReading] = []

        for sensor in sensors {
            guard let value = sensor.refreshValue() else {
                continue
            }

            baseReadings.append(
                UnifiedTemperatureReading(
                source: sensor.source,
                rawName: sensor.rawName,
                displayName: sensor.displayName,
                valueCelsius: value,
                group: sensor.group,
                type: sensor.type,
                sortKey: sensor.sortKey
            )
            )
        }

        let aggregateReadings: [UnifiedTemperatureReading] = AggregateTemperatureFactory.makeReadings(from: baseReadings)
        var combinedReadings = aggregateReadings + baseReadings
        combinedReadings.sort { lhs, rhs in
            lhs.sortKey.localizedCaseInsensitiveCompare(rhs.sortKey) == .orderedAscending
        }

        return combinedReadings
    }
}

enum AggregateTemperatureFactory {
    static func makeReadings(from baseReadings: [UnifiedTemperatureReading]) -> [UnifiedTemperatureReading] {
        AggregateRule.allCases.compactMap { rule in
            guard let value = rule.computeValue(from: baseReadings) else {
                return nil
            }

            return UnifiedTemperatureReading(
                source: .aggregate,
                rawName: rule.rawName,
                displayName: rule.displayName,
                valueCelsius: value,
                group: rule.group,
                type: rule.type,
                sortKey: rule.sortKey
            )
        }
    }
}

private enum AggregateRule: CaseIterable {
    case cpuEfficiencyCoresAverage
    case cpuPerformanceCoresAverage
    case cpuCoreAverage
    case gpuClusterAverage

    var rawName: String {
        switch self {
        case .cpuEfficiencyCoresAverage:
            return "cpu_efficiency_cores_average"
        case .cpuPerformanceCoresAverage:
            return "cpu_performance_cores_average"
        case .cpuCoreAverage:
            return "cpu_core_average"
        case .gpuClusterAverage:
            return "gpu_cluster_average"
        }
    }

    var displayName: String {
        switch self {
        case .cpuEfficiencyCoresAverage:
            return "CPU Efficiency Cores Average"
        case .cpuPerformanceCoresAverage:
            return "CPU Performance Cores Average"
        case .cpuCoreAverage:
            return "CPU Core Average"
        case .gpuClusterAverage:
            return "GPU Cluster Average"
        }
    }

    var group: String? {
        switch self {
        case .gpuClusterAverage:
            return "GPU"
        default:
            return "CPU"
        }
    }

    var type: String? {
        switch self {
        case .gpuClusterAverage:
            return "gpu"
        default:
            return "cpu"
        }
    }

    var sortKey: String {
        switch self {
        case .cpuEfficiencyCoresAverage:
            return "0-aggregate-cpu-efficiency"
        case .cpuPerformanceCoresAverage:
            return "0-aggregate-cpu-performance"
        case .cpuCoreAverage:
            return "0-aggregate-cpu-core"
        case .gpuClusterAverage:
            return "0-aggregate-gpu-cluster"
        }
    }

    func computeValue(from readings: [UnifiedTemperatureReading]) -> Double? {
        let matching: [UnifiedTemperatureReading]

        switch self {
        case .cpuEfficiencyCoresAverage:
            matching = readings.filter { $0.group == "CPU Efficiency Cores Average" }
        case .cpuPerformanceCoresAverage:
            matching = readings.filter { $0.group == "CPU Performance Cores Average" }
        case .cpuCoreAverage:
            let preferred = readings.filter {
                guard let type = $0.type else {
                    return false
                }
                return type.hasPrefix("cpu")
            }
            if !preferred.isEmpty {
                matching = preferred
            } else {
                matching = readings.filter { $0.group == "CPU" }
            }
        case .gpuClusterAverage:
            let preferred = readings.filter { $0.type == "gpu" }
            if !preferred.isEmpty {
                matching = preferred
            } else {
                matching = readings.filter { $0.source == .gpu }
            }
        }

        guard !matching.isEmpty else {
            return nil
        }

        return matching.map(\.valueCelsius).reduce(0, +) / Double(matching.count)
    }
}

struct DiskTemperatureProvider: TemperatureSensorProvider {
    func loadSensors() -> [any TemperatureSensor] {
        // The disk path is part of the original MFC provider graph, but this repo
        // still lacks a verified SMART / NVMe temperature implementation.
        // Keep the provider slot in the unified inventory so the architecture is
        // ready for it, without pretending we have a trustworthy read path yet.
        []
    }
}

struct SMCTemperatureProvider: TemperatureSensorProvider {
    private let runtime: TemperatureRuntime

    init(runtime: TemperatureRuntime) {
        self.runtime = runtime
    }

    func loadSensors() -> [any TemperatureSensor] {
        guard let connection = runtime.smcConnection else {
            return []
        }

        return Self.candidates.map {
            SMCTemperatureSensor(connection: connection, candidate: $0)
        }
    }

    private static let candidates: [SMCSensorCandidate] = {
        var sensors: [SMCSensorCandidate] = [
            .init(key: "TC0D", label: "CPU diode", group: "CPU", type: "cpu"),
            .init(key: "TC0P", label: "CPU proximity", group: "CPU", type: "cpu"),
            .init(key: "TC0E", label: "CPU die", group: "CPU", type: "cpu"),
            .init(key: "TC0F", label: "CPU PECI", group: "CPU", type: "cpu"),
            .init(key: "TC0C", label: "CPU core", group: "CPU", type: "cpu"),
            .init(key: "TCAD", label: "CPU analog digital", group: "CPU", type: "cpu"),
            .init(key: "TC0H", label: "CPU heatsink", group: "CPU", type: "cpu"),
            .init(key: "TCAH", label: "CPU A heatsink", group: "CPU", type: "cpu"),
            .init(key: "TCBH", label: "CPU B heatsink", group: "CPU", type: "cpu"),
            .init(key: "TB0T", label: "Battery", group: "Battery", type: "battery"),
            .init(key: "Tm0P", label: "Memory controller", group: "Memory", type: "memory"),
            .init(key: "Th0H", label: "Heat sink", group: "Thermal", type: "heatsink"),
            .init(key: "Ts0P", label: "Palm rest", group: "Thermal", type: "surface")
        ]

        #if arch(arm64)
        if let family = AppleSiliconPlatform.currentFamily() {
            sensors += AppleSiliconSMCReference.temperatureCandidates(for: family)
        }
        #endif

        return deduplicatedCandidates(sensors)
    }()

    private static func deduplicatedCandidates(_ candidates: [SMCSensorCandidate]) -> [SMCSensorCandidate] {
        var candidatesByKey: [String: SMCSensorCandidate] = [:]
        for candidate in candidates {
            candidatesByKey[candidate.key] = candidate
        }

        return candidatesByKey.values.sorted {
            $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }
    }
}

struct SMCSensorCandidate {
    let key: String
    let label: String
    let group: String?
    let type: String?
    let minimumUsableValue: Double

    init(key: String, label: String, group: String?, type: String?, minimumUsableValue: Double = 10) {
        self.key = key
        self.label = label
        self.group = group
        self.type = type
        self.minimumUsableValue = minimumUsableValue
    }
}

private final class SMCTemperatureSensor: TemperatureSensor {
    let source: TemperatureSource = .smc
    let rawName: String
    let displayName: String
    let group: String?
    let type: String?
    let sortKey: String

    private let connection: SMCConnection
    private let minimumUsableValue: Double

    init(connection: SMCConnection, candidate: SMCSensorCandidate) {
        self.connection = connection
        self.rawName = candidate.key
        self.displayName = candidate.label
        self.group = candidate.group
        self.type = candidate.type
        self.sortKey = "1-\(candidate.key)"
        self.minimumUsableValue = candidate.minimumUsableValue
    }

    func refreshValue() -> Double? {
        guard let value = try? connection.readTemperature(key: rawName) else {
            return nil
        }
        guard value >= minimumUsableValue, value < 127 else {
            return nil
        }
        return value
    }
}

struct GPUTemperatureProvider: TemperatureSensorProvider {
    private let runtime: TemperatureRuntime

    init(runtime: TemperatureRuntime) {
        self.runtime = runtime
    }

    func loadSensors() -> [any TemperatureSensor] {
        _ = discoverGPUs()
        return []
    }

    private func discoverGPUs() -> [GPUDevice] {
        guard let matching = IOServiceMatching("AGXFamilyAccelerator") else {
            return []
        }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [GPUDevice] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry) }

            if let properties = copyProperties(for: entry) {
                let model = decodeGPUModel(from: properties) ?? "Apple GPU"
                let coreCount = numericProperty(named: "gpu-core-count", in: properties)
                devices.append(GPUDevice(displayName: model, coreCount: coreCount))
            }

            entry = IOIteratorNext(iterator)
        }

        return devices
    }

    private func copyProperties(for entry: io_registry_entry_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS else {
            return nil
        }
        return properties?.takeRetainedValue() as? [String: Any]
    }

    private func decodeGPUModel(from properties: [String: Any]) -> String? {
        if let model = properties["model"] as? String {
            return model.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let modelData = properties["model"] as? Data,
           let model = String(data: modelData, encoding: .utf8) {
            return model.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
        }

        return nil
    }

    private func numericProperty(named key: String, in properties: [String: Any]) -> Int? {
        if let number = properties[key] as? NSNumber {
            return number.intValue
        }
        return nil
    }
}

private struct GPUDevice {
    let displayName: String
    let coreCount: Int?
}
