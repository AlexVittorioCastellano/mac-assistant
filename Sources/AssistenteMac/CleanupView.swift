import AppKit
import AssistenteCore
import SwiftUI

struct CleanupView: View {
    @Bindable var model: AssistantViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L.t("ui.cleanup.found", model.cleanupItems.count),
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
                    Button(L.t("ui.cleanup.showInFinder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
                }
            }

            Button {
                model.confirmCleanup = true
            } label: {
                Label(model.cleanupSelected.isEmpty ? L.t("ui.cleanup.tick")
                      : L.t("ui.cleanup.move", model.sizeText(model.selectedCleanupBytes)),
                      systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.cleanupSelected.isEmpty)
            Text(L.t("ui.cleanup.note"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert(L.t("ui.cleanup.confirm.title", model.selectedCleanupItems.count), isPresented: $model.confirmCleanup) {
            Button(L.t("ui.cleanup.confirm.button"), role: .destructive) { model.performCleanup() }
            Button(L.t("ui.cleanup.confirm.cancel"), role: .cancel) {}
        } message: {
            Text(model.selectedCleanupItems.prefix(8).map(\.name).joined(separator: "\n")
                 + (model.selectedCleanupItems.count > 8 ? "\n…" : "")
                 + "\n\n" + L.t("ui.cleanup.confirm.note"))
        }
    }
}
