import SwiftUI

struct LegalNoticesView: View {
    @State private var selectedDocument = LegalDocument.thirdPartyNotices

    var body: some View {
        VStack(spacing: 0) {
            Picker("Legal document", selection: $selectedDocument) {
                ForEach(LegalDocument.allCases) { document in
                    Text(document.title)
                        .tag(document)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .padding()

            Divider()

            ScrollView {
                Text(selectedDocument.contents)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .navigationTitle("Third-Party Licenses")
        #if os(macOS)
        .frame(width: 720, height: 620)
        #endif
    }
}

private enum LegalDocument: String, CaseIterable, Identifiable {
    case thirdPartyNotices = "THIRD-PARTY-NOTICES"
    case curl = "Curl-LICENSE"
    case curlApple = "CurlApple-LICENSE"
    case openSSL = "OpenSSL-LICENSE"
    case mozilla = "Mozilla-LICENSE"
    case skyLightWindow = "SkyLightWindow-LICENSE"

    var id: Self { self }

    var title: String {
        switch self {
        case .thirdPartyNotices: "Third-Party Notices"
        case .curl: "libcurl"
        case .curlApple: "curl-apple"
        case .openSSL: "OpenSSL"
        case .mozilla: "Mozilla CA Store"
        case .skyLightWindow: "SkyLightWindow"
        }
    }

    var contents: String {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "This legal document is unavailable in the application bundle."
        }
        return contents
    }
}

#Preview {
    NavigationStack {
        LegalNoticesView()
    }
}
