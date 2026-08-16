import SDMCore
import SwiftUI

struct DownloadConnectionsView: View {
    let snapshot: DownloadSnapshot

    var body: some View {
        if snapshot.segments.isEmpty {
            ContentUnavailableView {
                Label("No Range Segments", systemImage: "point.3.connected.trianglepath.dotted")
            } description: {
                if snapshot.engine == .urlSession {
                    Text("URLSession manages transfer ranges internally.")
                } else {
                    Text("Range segments appear after the server has been probed.")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Segments are scheduled byte ranges, not simultaneous connections. " +
                    "Idle connections can split large remaining ranges."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            #if os(macOS)
                Table(snapshot.segments) {
                    TableColumn("#") { segment in
                        Text(segment.ordinal + 1, format: .number)
                            .monospacedDigit()
                    }
                    .width(36)

                    TableColumn("Byte Range") { segment in
                        Text("\(segment.start.formatted())–\(segment.end.formatted())")
                            .monospacedDigit()
                            .textSelection(.enabled)
                    }
                    .width(min: 180, ideal: 240)

                    TableColumn("Downloaded") { segment in
                        Text(DownloadFormatting.bytes(segment.downloadedBytes))
                            .monospacedDigit()
                    }
                    .width(min: 90, ideal: 120)

                    TableColumn("Progress") { segment in
                        if let progress = segment.progressFraction {
                            ProgressView(value: progress) {
                                Text(progress, format: .percent.precision(.fractionLength(0)))
                                    .monospacedDigit()
                            }
                            .tint(snapshot.state.tint)
                        }
                    }
                    .width(min: 150, ideal: 200)
                }
            #else
                List(snapshot.segments) { segment in
                    MobileDownloadSegmentRow(segment: segment)
                }
                .listStyle(.insetGrouped)
            #endif
            }
        }
    }
}
