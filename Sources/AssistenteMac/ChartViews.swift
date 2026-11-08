import AppKit
import AssistenteCore
import Charts
import SwiftUI

enum ChartPalette {
    static let series: [(light: UInt32, dark: UInt32)] = [
        (0x2a78d6, 0x3987e5),
        (0xeb6834, 0xd95926),
        (0x1baf7a, 0x199e70),
        (0xeda100, 0xc98500),
        (0xe87ba4, 0xd55181),
    ]

    static let rest: (light: UInt32, dark: UInt32) = (0x9e9d97, 0x6b6a65)

    static func color(_ swatch: ChartSwatch) -> Color {
        switch swatch {
        case .series(let i): adaptive(series[i % series.count])
        case .rest: adaptive(rest)
        }
    }

    static func adaptive(_ pair: (light: UInt32, dark: UInt32)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return nsColor(hex: dark ? pair.dark : pair.light)
        })
    }

    static func nsColor(hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

struct DiskChartView: View {
    let chart: SegmentedChart

    @Binding var hover: Double?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            donut
            if let summary = chart.capacitySummary, let capacity = chart.capacityBytes {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary)
                        .font(.callout.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    CapacityMeter(fraction: Double(chart.totalBytes) / Double(max(capacity, 1)), level: chart.level)
                    Text(L.t("ui.chart.caption"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var visible: [SegmentedChart.Segment] { chart.segments.filter { $0.bytes > 0 } }

    private var hovered: SegmentedChart.Segment? {
        guard let hover else { return nil }
        var running = 0.0
        for s in visible {
            running += Double(s.bytes)
            if hover <= running { return s }
        }
        return nil
    }

    private var donut: some View {
        Chart(visible) { segment in
            SectorMark(angle: .value("Spazio", Double(segment.bytes)),
                       innerRadius: .ratio(0.62),
                       angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(ChartPalette.color(segment.swatch))

                .opacity(hovered == nil || hovered?.id == segment.id ? 1 : 0.35)
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: $hover)
        .chartBackground { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame {
                    let rect = geo[frame]
                    centerLabel
                        .frame(width: rect.width * 0.55)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("ui.chart.a11y", chart.segments.map(chart.description).joined(separator: ", ")))
    }

    @ViewBuilder private var centerLabel: some View {
        VStack(spacing: 1) {
            if let s = hovered {
                Text(chart.amount(of: s))
                    .font(.headline)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                Text("\(s.label) · \(chart.share(of: s))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            } else {
                Text(chart.totalLabel)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                Text(L.t("ui.chart.used"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }
}

struct CapacityMeter: View {
    let fraction: Double
    let level: Finding.Severity

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule().fill(fill).frame(width: max(8, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private var fill: Color {
        switch level {
        case .critical: .red
        case .warning: .orange
        default: ChartPalette.adaptive(ChartPalette.series[0])
        }
    }
}

struct SwatchDot: View {
    let swatch: ChartSwatch

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(ChartPalette.color(swatch))
            .frame(width: 10, height: 10)
    }
}
