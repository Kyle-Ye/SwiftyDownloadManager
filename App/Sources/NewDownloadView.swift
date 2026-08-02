import SwiftUI

struct NewDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var connectionCount: Int
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    let destinationDirectory: URL
    private let onSubmit: @MainActor (URL, Int) async throws -> Void

    init(
        defaultConnectionCount: Int,
        destinationDirectory: URL,
        onSubmit: @escaping @MainActor (URL, Int) async throws -> Void
    ) {
        _connectionCount = State(initialValue: defaultConnectionCount)
        self.destinationDirectory = destinationDirectory
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

                Stepper("Connections: \(connectionCount)", value: $connectionCount, in: 1 ... 16)

                LabeledContent("Destination") {
                    Text(destinationDirectory.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
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
                            try await onSubmit(validatedURL, connectionCount)
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
        .frame(width: 560)
        .interactiveDismissDisabled(isSubmitting)
    }
}

#Preview {
    NewDownloadView(
        defaultConnectionCount: 8,
        destinationDirectory: FileManager.default.temporaryDirectory
    ) { _, _ in }
}
