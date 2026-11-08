import AppKit
import AssistenteCore
import SwiftUI

/// Pulizia guidata: elenco di file con casella da spuntare. Niente si muove
/// senza la conferma dell'avviso; i file vanno nel Cestino (recuperabili).
struct CleanupView: View {
    @Bindable var model: AssistantViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ho trovato \(model.cleanupItems.count) file che potresti togliere. Spunta quelli che non ti servono.",
                  systemImage: "sparkles")
                .fixedSize(horizontal: false, vertical: true)

            ForEach(model.cleanupItems) { item in
                Button { model.toggleCleanup(item) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: model.cleanupSelected.contains(item.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(model.cleanupSelected.contains(item.id) ? Color.accentColor : Color.secondary)
                            .font(.title3)
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                            .resizable().frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(item.name).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 4)
                                Text(model.sizeText(item.bytes)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            Text(item.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.path)
                .contextMenu {
                    Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
                }
            }

            Button {
                model.confirmCleanup = true
            } label: {
                Label(model.cleanupSelected.isEmpty ? "Spunta i file da togliere"
                      : "Sposta nel Cestino (\(model.sizeText(model.selectedCleanupBytes)))",
                      systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.cleanupSelected.isEmpty)
            Text("I file vanno nel Cestino: puoi recuperarli finché non lo svuoti. Clic destro su un file per vederlo nel Finder.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert("Spostare \(model.selectedCleanupItems.count) file nel Cestino?", isPresented: $model.confirmCleanup) {
            Button("Sposta nel Cestino", role: .destructive) { model.performCleanup() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text(model.selectedCleanupItems.prefix(8).map(\.name).joined(separator: "\n")
                 + (model.selectedCleanupItems.count > 8 ? "\n…" : "")
                 + "\n\nPotrai recuperarli dal Cestino finché non lo svuoti.")
        }
    }
}
