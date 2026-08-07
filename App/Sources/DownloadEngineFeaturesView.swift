#if os(iOS)
import SDMCore
import SwiftUI

struct DownloadEngineFeaturesView: View {
    let descriptor: DownloadEngineDescriptor

    var body: some View {
        List {
            Section("Selected Engine") {
                LabeledContent("Engine", value: descriptor.kind.title)
                LabeledContent("Version", value: descriptor.version)
            }

            Section("Capabilities") {
                ForEach(DownloadFeature.allCases) { feature in
                    Label {
                        Text(feature.title)
                    } icon: {
                        Image(
                            systemName: descriptor.supports(feature)
                                ? "checkmark.circle.fill"
                                : "xmark.circle"
                        )
                        .foregroundStyle(
                            descriptor.supports(feature) ? Color.green : Color.secondary
                        )
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(feature.title)
                    .accessibilityValue(
                        descriptor.supports(feature) ? "Supported" : "Not supported"
                    )
                }
            }
        }
        .navigationTitle("Engine Capabilities")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
