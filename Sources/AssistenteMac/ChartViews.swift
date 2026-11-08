import AppKit
import AssistenteCore
import SwiftUI

/// Colori dei grafici.
///
/// Palette categoriale in ordine fisso (blu, arancio, acqua, giallo, magenta),
/// con una versione per il tema chiaro e una per lo scuro. Verificata per
/// distinguibilità anche con daltonismo (ΔE adiacenti ≥ 8 in OKLab) su
/// entrambi gli sfondi. Sul chiaro alcuni colori hanno contrasto < 3:1: va
/// bene perché ogni parte è anche scritta per esteso nell'elenco sotto.
enum ChartPalette {
    static let series: [(light: UInt32, dark: UInt32)] = [
        (0x2a78d6, 0x3987e5),  // blu
        (0xeb6834, 0xd95926),  // arancio
        (0x1baf7a, 0x199e70),  // acqua
        (0xeda100, 0xc98500),  // giallo
        (0xe87ba4, 0xd55181),  // magenta
    ]
    /// "Il resto": grigio neutro, non è una categoria.
    static let rest: (light: UInt32, dark: UInt32) = (0x9e9d97, 0x6b6a65)

    static func color(_ swatch: ChartSwatch) -> Color {
        switch swatch {
        case .series(let i): adaptive(series[i % series.count])
        case .rest: adaptive(rest)
        }
    }

    /// Colore che cambia da solo con il tema chiaro/scuro.
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

    /// Testo leggibile sopra un blocco colorato: bianco o quasi nero,
    /// quello con più contrasto.
    static func label(on swatch: ChartSwatch, dark: Bool) -> Color {
        let hex: UInt32
        switch swatch {
        case .series(let i): hex = dark ? series[i % series.count].dark : series[i % series.count].light
        case .rest: hex = dark ? rest.dark : rest.light
        }
        func lin(_ c: UInt32) -> Double {
            let v = Double(c) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let l = 0.2126 * lin((hex >> 16) & 0xff) + 0.7152 * lin((hex >> 8) & 0xff) + 0.0722 * lin(hex & 0xff)
        let whiteContrast = 1.05 / (l + 0.05)
        let blackContrast = (l + 0.05) / (0.0 + 0.05)
        return whiteContrast >= blackContrast ? .white : Color(white: 0.08)
    }
}

/// Il grafico dello spazio: un indicatore sottile "usati X su Y" e sotto
/// una barra segmentata che mostra come è diviso lo spazio usato. Ogni
/// blocco ha la percentuale dentro se ci sta; passando il mouse si leggono
/// nome e quantità. Le righe sotto (con il pallino dello stesso colore)
/// fanno da legenda.
struct SegmentedBar: View {
    let chart: SegmentedChart
    @Environment(\.colorScheme) private var colorScheme

    private let height: CGFloat = 26
    private let gap: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = chart.capacitySummary, let capacity = chart.capacityBytes {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary).font(.callout.weight(.medium))
                    CapacityMeter(fraction: Double(chart.totalBytes) / Double(max(capacity, 1)), level: chart.level)
                }
                Text("Come è diviso lo spazio usato")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            bar
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            let visible = chart.segments.filter { $0.bytes > 0 }
            let available = geo.size.width - gap * CGFloat(max(visible.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(visible) { segment in
                    block(segment, width: max(3, available * share(segment)))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spazio usato: " + chart.segments.map(chart.description).joined(separator: ", "))
    }

    private func share(_ s: SegmentedChart.Segment) -> CGFloat {
        chart.totalBytes > 0 ? CGFloat(Double(s.bytes) / Double(chart.totalBytes)) : 0
    }

    private func block(_ s: SegmentedChart.Segment, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(ChartPalette.color(s.swatch))
            .frame(width: width)
            .overlay(alignment: .leading) {
                // Percentuale solo se il blocco è abbastanza largo da contenerla.
                if width >= 38 {
                    Text(Fmt_percent(share(s) * 100))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(ChartPalette.label(on: s.swatch, dark: colorScheme == .dark))
                        .padding(.leading, 5)
                }
            }
            .help(chart.description(of: s))
    }
}

/// Indicatore sottile di riempimento: blu se va tutto bene, arancio se lo
/// spazio sta finendo, rosso se è quasi esaurito (la riga "Spazio libero"
/// sotto lo dice anche a parole, con la sua icona).
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
        .accessibilityHidden(true)  // il testo sopra dice già tutto
    }

    private var fill: Color {
        switch level {
        case .critical: .red
        case .warning: .orange
        default: ChartPalette.adaptive(ChartPalette.series[0])
        }
    }
}

/// Pallino colorato a sinistra di una riga dell'elenco.
struct SwatchDot: View {
    let swatch: ChartSwatch

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(ChartPalette.color(swatch))
            .frame(width: 10, height: 10)
    }
}

/// "35%" con il formato italiano.
private func Fmt_percent(_ value: CGFloat) -> String {
    Int(value.rounded()).formatted(.number.locale(Locale(identifier: "it_IT"))) + "%"
}
