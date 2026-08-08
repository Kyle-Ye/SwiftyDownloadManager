import SDMCore
import SwiftUI

struct DownloadOverviewView: View {
    let snapshot: DownloadSnapshot
    let fallbackDirectory: URL

    private var savedLocation: URL {
        snapshot.destinationURL ?? fallbackDirectory
    }

    var body: some View {
        Form {
            Section("Transfer") {
                LabeledContent("Engine", value: snapshot.engine.title)
                LabeledContent("Size", value: DownloadFormatting.bytes(snapshot.contentLength))
                LabeledContent(
                    "Downloaded",
                    value: DownloadFormatting.bytes(snapshot.downloadedBytes)
                )
                LabeledContent("Speed", value: DownloadFormatting.speed(snapshot.bytesPerSecond))
                LabeledContent(
                    "Remaining",
                    value: DownloadFormatting.duration(snapshot.estimatedTimeRemaining)
                )
                LabeledContent("Connections", value: snapshot.segments.count.formatted())
            }

            Section("Location") {
                LabeledContent("Saved to") {
                    Text(savedLocation.path(percentEncoded: false))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Section("Source") {
                LabeledContent("URL") {
                    Text(snapshot.sourceURL.absoluteString)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if let finalURL = snapshot.finalURL,
                   finalURL != snapshot.sourceURL {
                    LabeledContent("Final URL") {
                        Text(finalURL.absoluteString)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }

            if let error = snapshot.error {
                Section("Error") {
                    LabeledContent("Code", value: error.code.rawValue.formatted())
                    Text(error.message)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section("Activity") {
                LabeledContent("Added") {
                    Text(snapshot.createdAt, format: .dateTime)
                        .textSelection(.enabled)
                }
                if let lastAttemptAt = snapshot.lastAttemptAt {
                    LabeledContent("Last try") {
                        Text(lastAttemptAt, format: .dateTime)
                            .textSelection(.enabled)
                    }
                }
                if let completedAt = snapshot.completedAt {
                    LabeledContent("Completed") {
                        Text(completedAt, format: .dateTime)
                            .textSelection(.enabled)
                    }
                }
                LabeledContent("Last updated") {
                    Text(snapshot.updatedAt, format: .dateTime)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}
