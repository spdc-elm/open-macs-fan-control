import Foundation
import IOKit.hidsystem

struct IOHIDTemperatureReading {
    let name: String
    let valueCelsius: Double
    let serviceIndex: Int
}

enum IOHIDTemperatureProbe {
    private static let primaryUsagePage = 0xFF00
    private static let primaryUsage = 5
    private static let temperatureEventType: Int64 = 15
    private static let temperatureField: Int32 = Int32(15 << 16)

    static func readAll() -> [IOHIDTemperatureReading] {
        let services = loadServices().enumerated().compactMap { index, service in
            makeReading(from: service, serviceIndex: index)
        }

        return services.sorted {
            if $0.name == $1.name {
                return $0.serviceIndex < $1.serviceIndex
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func loadSensors(metadataByRawName: [String: IOHIDSensorMetadata]) -> [any TemperatureSensor] {
        let context = IOHIDContext(client: IOHIDEventSystemClientCreate(kCFAllocatorDefault))
        guard let client = context.client else {
            return []
        }

        let matching: CFDictionary = [
            kIOHIDPrimaryUsagePageKey: primaryUsagePage,
            kIOHIDPrimaryUsageKey: primaryUsage
        ] as CFDictionary
        _ = IOHIDEventSystemClientSetMatching(client, matching)

        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            return []
        }

        return services.enumerated().compactMap { index, service in
            let name = (IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) as? String) ?? "Unnamed IOHID sensor"
            return IOHIDLoadedTemperatureSensor(
                context: context,
                service: service,
                rawName: name,
                serviceIndex: index,
                metadata: metadataByRawName[name]
            )
        }
    }

    private static func loadServices() -> [IOHIDServiceClient] {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
            return []
        }

        let matching: CFDictionary = [
            kIOHIDPrimaryUsagePageKey: primaryUsagePage,
            kIOHIDPrimaryUsageKey: primaryUsage
        ] as CFDictionary

        _ = IOHIDEventSystemClientSetMatching(client, matching)

        return (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]) ?? []
    }

    fileprivate static func readValue(from service: IOHIDServiceClient) -> Double? {
        guard let event = IOHIDServiceClientCopyEvent(service, temperatureEventType, 0, 0)?.takeRetainedValue() else {
            return nil
        }

        let value = IOHIDEventGetFloatValue(event, temperatureField)
        guard value > 0 else {
            return nil
        }

        return value
    }

    private static func makeReading(from service: IOHIDServiceClient, serviceIndex: Int) -> IOHIDTemperatureReading? {
        guard let value = readValue(from: service) else {
            return nil
        }

        let name = (IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) as? String) ?? "Unnamed IOHID sensor"
        return IOHIDTemperatureReading(name: name, valueCelsius: value, serviceIndex: serviceIndex)
    }
}

struct IOHIDTemperatureProvider: TemperatureSensorProvider {
    func loadSensors() -> [any TemperatureSensor] {
        IOHIDTemperatureProbe.loadSensors(metadataByRawName: IOHIDSensorMetadataStore.shared)
    }
}

private final class IOHIDContext {
    let client: IOHIDEventSystemClient?

    init(client: IOHIDEventSystemClient?) {
        self.client = client
    }
}

private final class IOHIDLoadedTemperatureSensor: TemperatureSensor {
    let source: TemperatureSource = .iohid
    let rawName: String
    let displayName: String
    let group: String?
    let type: String?
    let sortKey: String

    private let context: IOHIDContext
    private let service: IOHIDServiceClient

    init(
        context: IOHIDContext,
        service: IOHIDServiceClient,
        rawName: String,
        serviceIndex: Int,
        metadata: IOHIDSensorMetadata?
    ) {
        self.context = context
        self.service = service
        self.rawName = rawName
        self.displayName = metadata?.friendlyName ?? rawName
        self.group = metadata?.group
        self.type = metadata?.type
        self.sortKey = "0-\(rawName)-\(String(format: "%04d", serviceIndex))"
    }

    func refreshValue() -> Double? {
        guard context.client != nil else {
            return nil
        }
        return IOHIDTemperatureProbe.readValue(from: service)
    }
}

private typealias IOHIDEventRef = CFTypeRef

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> IOHIDEventSystemClient?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClient, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(
    _ service: IOHIDServiceClient,
    _ eventType: Int64,
    _ options: Int32,
    _ timestamp: Int64
) -> Unmanaged<IOHIDEventRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: IOHIDEventRef, _ field: Int32) -> Double
