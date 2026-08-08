import SwiftUI
import UniformTypeIdentifiers
import SDMCore

struct NewDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var connectionCount: Int
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showsDestinationPicker = false
    @State private var destinationDirectory: URL
    let engine: DownloadEngineDescriptor

    private let onSubmit: @MainActor (URL, URL, Int) async throws -> Void

    init(
        defaultConnectionCount: Int,
        destinationDirectory: URL,
        engine: DownloadEngineDescriptor,
        onSubmit: @escaping @MainActor (URL, URL, Int) async throws -> Void
    ) {
        _connectionCount = State(initialValue: defaultConnectionCount)
        _destinationDirectory = State(initialValue: destinationDirectory)
        self.engine = engine
        self.onSubmit = onSubmit
    }

    private var validatedURL: URL? {
        guard let url = URL(string: urlText),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }

        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Download")
                .font(.title2.bold())

            Form {
                TextField("URL", text: $urlText, prompt: Text("https://example.com/file.zip"))
                    .textFieldStyle(.roundedBorder)

                LabeledContent("Engine", value: engine.kind.title)

                if engine.supports(.multiConnectionTransfers) {
                    Stepper(
                        "Connections: \(connectionCount)",
                        value: $connectionCount,
                        in: 1 ... engine.maximumConnectionsPerDownload
                    )
                } else {
                    LabeledContent("Connections", value: "Managed by URLSession")
                }

                LabeledContent("Destination") {
                    HStack {
                        Text(destinationDirectory.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") {
                            showsDestinationPicker = true
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSubmitting)

                Button("Add") {
                    guard let validatedURL else { return }
                    Task { @MainActor in
                        isSubmitting = true
                        errorMessage = nil
                        defer { isSubmitting = false }
                        do {
                            try await onSubmit(
                                validatedURL,
                                destinationDirectory,
                                effectiveConnectionCount
                            )
                            dismiss()
                        } catch {
                            errorMessage = DownloadService.message(for: error)
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(validatedURL == nil || isSubmitting)

                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 560)
        #endif
        .interactiveDismissDisabled(isSubmitting)
        .fileImporter(
            isPresented: $showsDestinationPicker,
            allowedContentTypes: [.folder]
        ) { result in
            do {
                destinationDirectory = try result.get()
                errorMessage = nil
            } catch {
                errorMessage = DownloadService.message(for: error)
            }
        }
    }

    private var effectiveConnectionCount: Int {
        engine.supports(.multiConnectionTransfers) ? connectionCount : 1
    }
}

#Preview {
    NewDownloadView(
        defaultConnectionCount: 8,
        destinationDirectory: FileManager.default.temporaryDirectory,
        engine: DownloadEngineDescriptor(
            kind: .libcurl,
            version: "8.21.0",
            features: [.multiConnectionTransfers],
            maximumConnectionsPerDownload: 16
        )
    ) { _, _, _ in }
}
