import FanControlRuntime
import SwiftUI

/// The SwiftUI content that gets rendered into the menu bar label image.
/// Three columns: CPU/temp, GPU/temp, Fan/rpm, plus a colored status dot.
private struct StatusItemLabelContent: View {
    let snapshot: TelemetrySnapshot
    let controllerStatus: AutomaticControlStatusSnapshot
    let controllerErrorMessage: String?

    var body: some View {
        HStack(spacing: 5) {
            column(title: "CPU", value: formatTemperature(snapshot.cpuAverageCelsius))
            column(title: "GPU", value: formatTemperature(snapshot.gpuAverageCelsius))
            column(title: "Mem", value: formatTemperature(snapshot.memoryAverageCelsius))
            column(title: "Fan", value: formatFanSummary(snapshot.fanSummary))

            Circle()
                .fill(indicatorColor)
                .frame(width: 6, height: 6)
        }
    }

    private func column(title: String, value: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
        }
    }

    private func formatTemperature(_ value: TelemetryValue<Double>) -> String {
        guard let temperature = value.value else { return "--" }
        return "\(Int(temperature.rounded()))°"
    }

    private func formatFanSummary(_ summary: FanTelemetrySummary) -> String {
        guard let averageCurrentRPM = summary.averageCurrentRPM else { return "--" }
        let compact = Double(averageCurrentRPM) / 1000
        return "\(String(format: "%.1f", compact))k"
    }

    private var indicatorColor: Color {
        if controllerErrorMessage != nil || controllerStatus.phase == .failed {
            return .red
        }
        switch controllerStatus.phase {
        case .idle: return .gray
        case .starting, .stopping: return .red
        case .running: return .green
        case .failed: return .red
        }
    }
}

/// The actual label used inside MenuBarExtra.
/// Renders `StatusItemLabelContent` to an NSImage via ImageRenderer,
/// so we get multi-line colored content in the system menu bar.
struct StatusItemLabel: View {
    let snapshot: TelemetrySnapshot
    let controllerStatus: AutomaticControlStatusSnapshot
    let controllerErrorMessage: String?

    var body: some View {
        let content = StatusItemLabelContent(
            snapshot: snapshot,
            controllerStatus: controllerStatus,
            controllerErrorMessage: controllerErrorMessage
        )
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0

        if let nsImage = renderer.nsImage {
            nsImage.isTemplate = false
            return Image(nsImage: nsImage)
        } else {
            return Image(systemName: "thermometer.medium")
        }
    }
}
