import SDMCore
import SwiftUI

struct DownloadSidebar: View {
    let snapshots: [DownloadSnapshot]
    @Binding var selection: DownloadFilter?

    var body: some View {
        List(DownloadFilter.allCases, selection: $selection) { filter in
            HStack {
                Label(filter.rawValue, systemImage: filter.systemImage)
                Spacer()
                Text(filterCount(filter), format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .tag(filter)
        }
        .navigationTitle("Downloads")
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
    }

    private func filterCount(_ filter: DownloadFilter) -> Int {
        snapshots.count { filter.includes($0.state) }
    }
}
