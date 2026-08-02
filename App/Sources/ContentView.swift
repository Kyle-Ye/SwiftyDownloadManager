import SDMCore
import SwiftUI

struct ContentView: View {
    @State private var selection: DownloadFilter? = .all
    @State private var showsNewDownload = false

    var body: some View {
        NavigationSplitView {
            List(DownloadFilter.allCases, selection: $selection) { filter in
                Label(filter.rawValue, systemImage: filter.systemImage)
                    .tag(filter)
            }
            .navigationTitle("Downloads")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            ContentUnavailableView {
                Label("No Downloads", systemImage: "arrow.down.circle")
            } description: {
                Text("Add a direct HTTP or HTTPS URL to start a download.")
            } actions: {
                Button("New Download") {
                    showsNewDownload = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            .navigationTitle(selection?.rawValue ?? "Downloads")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Download", systemImage: "plus") {
                        showsNewDownload = true
                    }
                }
            }
        }
        .sheet(isPresented: $showsNewDownload) {
            NewDownloadView()
        }
    }
}

#Preview {
    ContentView()
}
