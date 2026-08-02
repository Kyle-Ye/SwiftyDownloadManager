import SDMCore
import SwiftUI

struct DownloadLogView: View {
    let entries: [DownloadDiagnosticEvent]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Activity History")
                    .font(.headline)
                Text("Up to 500 recent events")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy Log", systemImage: "doc.on.doc", action: copyLog)
                    .disabled(entries.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No Log Entries", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Download activity will appear here as it occurs.")
                }
            } else {
                ScrollViewReader { proxy in
                    List(entries) { entry in
                        DownloadLogRow(entry: entry)
                            .id(entry.id)
                    }
                    .task {
                        if let lastID = entries.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                    .onChange(of: entries.count) { _, _ in
                        if let lastID = entries.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func copyLog() {
        let text = entries.map { entry in
            let timestamp = entry.timestamp.formatted(
                .dateTime.year().month().day().hour().minute().second()
            )
            return "\(timestamp) [\(entry.level.title.uppercased())] \(entry.message)"
        }
        .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
