import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: HistoryStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    ContentUnavailableView(
                        L10n.text("还没有记录", "No history yet", language: settings.language),
                        systemImage: "clock.arrow.circlepath",
                        description: Text(L10n.text(
                            "完成一次输入后，原始转写和结果会保存在本机。",
                            "After a successful input, the original transcript and result stay on this device.",
                            language: settings.language
                        ))
                    )
                } else {
                    List {
                        ForEach(history.entries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(modeTitle(entry.mode)).font(.caption.weight(.semibold)).foregroundStyle(.blue)
                                    Spacer()
                                    Text(entry.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(entry.originalTranscript).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                if !entry.result.isEmpty {
                                    Divider()
                                    Text(entry.result).font(.body).lineLimit(5).textSelection(.enabled)
                                } else if let error = entry.error {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(entry.outcome == "cancelled" ? Color.secondary : Color.red)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle(L10n.text("历史", "History", language: settings.language))
        }
    }

    private func modeTitle(_ rawValue: String) -> String {
        if rawValue == "selectedEdit" {
            return L10n.text("选中修改", "Edit Selection", language: settings.language)
        }
        return InputMode(rawValue: rawValue)?.title(settings.language) ?? rawValue
    }
}
