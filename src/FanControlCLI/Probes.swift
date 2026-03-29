import Foundation
import FanControlRuntime

struct TemperatureProbe {
    let options: TemperatureOptions

    func run() throws {
        print("# Temperature probe")
        print("# Multi-source inventory: IOHID + SMC + GPU fallback are loaded together and refreshed uniformly.")
        print("# Compare these values against a trusted external reference on the same machine.")

        let telemetry = TelemetryReader()
        let readings = telemetry.refresh().temperatures

        guard !readings.isEmpty else {
            throw CLIError("no readable temperature sensors were found from the current provider set")
        }

        let duplicateCounts = Dictionary(grouping: readings, by: { "\($0.source.rawValue)|\($0.rawName)" })
            .mapValues(\.count)
        var emittedCounts: [String: Int] = [:]

        for reading in readings {
            let duplicateKey = "\(reading.source.rawValue)|\(reading.rawName)"
            emittedCounts[duplicateKey, default: 0] += 1
            let displayName = formattedDisplayName(
                for: reading,
                occurrence: emittedCounts[duplicateKey] ?? 1,
                duplicateCount: duplicateCounts[duplicateKey] ?? 0
            )

            let formatted = String(format: "%.1f", reading.valueCelsius)
            print("\(reading.source.rawValue)\t\(displayName)\t\(formatted) °C")
        }
    }

    private func formattedDisplayName(
        for reading: UnifiedTemperatureReading,
        occurrence: Int,
        duplicateCount: Int
    ) -> String {
        let duplicateSuffix = duplicateCount > 1 ? " #\(occurrence)" : ""

        switch options.format {
        case .raw:
            return reading.rawName + duplicateSuffix
        case .friendly:
            var parts = [reading.displayName + duplicateSuffix]
            if let group = reading.group {
                parts.append("group=\(group)")
            }
            if let type = reading.type {
                parts.append("type=\(type)")
            }
            parts.append("raw=\(reading.rawName)")
            return parts.joined(separator: " | ")
        }
    }
}

struct FanProbe {
    let writer: any PrivilegedFanWriter

    func run() throws {
        print("# Fan probe")
        print("# Fan state is read through the root writer daemon.")
        for fan in try writer.inspectFans() {
            let target = fan.targetRPM.map(String.init) ?? "n/a"
            print("fan \(fan.index): current=\(fan.currentRPM)rpm min=\(fan.minimumRPM)rpm max=\(fan.maximumRPM)rpm target=\(target) mode=\(fan.modeDescription)")
        }
    }
}

struct FanWriteCommand {
    let writer: any PrivilegedFanWriter
    let options: WriteOptions

    func run() throws {
        let fanInventory = try writer.inspectFans()
        guard let fan = fanInventory.first(where: { $0.index == options.fanIndex }) else {
            throw CLIError("fan \(options.fanIndex) is unavailable from the root writer daemon")
        }
        let clampedTarget = max(fan.minimumRPM, min(fan.maximumRPM, options.rpm))

        print("# Manual write validation")
        print("# Manual writes are issued through the root writer daemon.")
        print("writerDaemonSocket=\(RootWriterDaemonPaths.socketPath)")
        print("fan \(fan.index): current=\(fan.currentRPM)rpm min=\(fan.minimumRPM)rpm max=\(fan.maximumRPM)rpm")

        let signalMonitor = SignalMonitor()
        defer { signalMonitor.stop() }

        var shouldRestore = true
        defer {
            if shouldRestore {
                do {
                    try writer.restoreAutomaticMode(fanIndices: [fan.index])
                    print("restored automatic mode for fan \(fan.index)")
                } catch {
                    FileHandle.standardError.write(Data(("warning: failed to restore automatic mode for fan \(fan.index): \(error.localizedDescription)\n").utf8))
                }
            }
        }

        try writer.applyTarget(fanIndex: fan.index, rpm: clampedTarget)
        print("requested target: \(clampedTarget)rpm")
        let holdSeconds = String(format: "%.1f", options.holdSeconds)
        print("observing for \(holdSeconds)s; press Ctrl-C for handled early exit")

        let deadline = Date().addingTimeInterval(options.holdSeconds)
        var nextPoll = Date()
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            if signalMonitor.terminationRequested {
                print("received handled termination signal; restoring automatic mode")
                break
            }

            if Date() >= nextPoll {
                guard let updated = try writer.inspectFans().first(where: { $0.index == fan.index }) else {
                    throw CLIError("fan \(fan.index) disappeared from the root writer daemon inventory")
                }
                let target = updated.targetRPM.map(String.init) ?? "n/a"
                print("readback: current=\(updated.currentRPM)rpm target=\(target) mode=\(updated.modeDescription)")
                nextPoll = Date().addingTimeInterval(options.verifyInterval)
            }
        }

        shouldRestore = true
    }
}
