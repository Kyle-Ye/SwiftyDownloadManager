import SwiftUI

struct NewDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var connectionCount = 8

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
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(validatedURL == nil)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

#Preview {
    NewDownloadView()
}
