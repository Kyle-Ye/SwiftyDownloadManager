import SDMCore
import SwiftUI

struct DownloadInfoHeaderView: View {
    let snapshot: DownloadSnapshot

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: snapshot.state.systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(snapshot.state.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading) {
                    Text(snapshot.displayFilename)
                        .font(.title2)
                        .bold()
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text(snapshot.sourceURL.host() ?? snapshot.sourceURL.absoluteString)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Label(snapshot.state.title, systemImage: snapshot.state.systemImage)
                    .foregroundStyle(snapshot.state.tint)
            }

            if let progress = snapshot.progressFraction {
                ProgressView(value: progress) {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
            } else if snapshot.state == .probing || snapshot.state == .downloading {
                ProgressView()
            }
        }
        .padding()
    }
}
