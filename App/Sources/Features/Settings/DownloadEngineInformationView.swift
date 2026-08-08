#if os(iOS)
import SDMCore
import SwiftUI

struct DownloadEngineInformationView: View {
    let descriptor: DownloadEngineDescriptor
    let databaseURL: URL?

    var body: some View {
        Form {
            Section("Engine") {
                LabeledContent("Selected", value: descriptor.kind.title)
                LabeledContent("Version", value: descriptor.version)
                LabeledContent("Runtime", value: SDMCoreInfo.engineVersion)
                LabeledContent("libcurl", value: SDMCoreInfo.libcurlVersion)
                LabeledContent("ABI") {
                    Text(SDMCoreInfo.engineABIVersion, format: .number)
                }
            }

            if let databaseURL {
                Section("Storage") {
                    LabeledContent("History database") {
                        Text(databaseURL.path(percentEncoded: false))
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Engine Information")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
