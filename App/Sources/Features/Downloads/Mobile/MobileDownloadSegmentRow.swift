#if os(iOS)
import SDMCore
import SwiftUI

struct MobileDownloadSegmentRow: View {
    let segment: DownloadSegmentSnapshot

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent("Connection", value: (segment.ordinal + 1).formatted())
            LabeledContent(
                "Byte range",
                value: "\(segment.start.formatted())–\(segment.end.formatted())"
            )
            LabeledContent(
                "Downloaded",
                value: DownloadFormatting.bytes(segment.downloadedBytes)
            )
            if let progress = segment.progressFraction {
                ProgressView(value: progress)
                    .accessibilityLabel("Connection progress")
                    .accessibilityValue(progress.formatted(.percent))
            }
        }
    }
}

#if DEBUG
#Preview("Download Segment Rows") {
    List(DownloadPreviewFixtures.segments) { segment in
        MobileDownloadSegmentRow(segment: segment)
    }
}
#endif
#endif
