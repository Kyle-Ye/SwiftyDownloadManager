import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling, @unchecked Sendable {
    private static let callbackScheme = "swifty-download-manager"

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let userInfo = item.userInfo as? [String: Any],
              let message = userInfo[SFExtensionMessageKey] as? [String: Any]
        else {
            reply(to: context, accepted: false, error: "The extension message was invalid.")
            return
        }

        switch message["type"] as? String {
        case "download":
            handleDownload(message, context: context)
        case "openApp":
            openCallback(host: "open", queryItems: [], context: context)
        default:
            reply(to: context, accepted: false, error: "The extension message type was unsupported.")
        }
    }

    private func handleDownload(
        _ message: [String: Any],
        context: NSExtensionContext
    ) {
        guard let urlText = message["url"] as? String,
              let downloadURL = URL(string: urlText),
              let scheme = downloadURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              downloadURL.host != nil
        else {
            reply(to: context, accepted: false, error: "Only HTTP and HTTPS downloads are supported.")
            return
        }

        var queryItems = [URLQueryItem(name: "url", value: downloadURL.absoluteString)]
        if let filename = nonEmptyString(message["filename"]) {
            queryItems.append(URLQueryItem(name: "filename", value: filename))
        }
        if let sourcePage = nonEmptyString(message["sourcePage"]) {
            queryItems.append(URLQueryItem(name: "source", value: sourcePage))
        }

        openCallback(host: "download", queryItems: queryItems, context: context)
    }

    private func openCallback(
        host: String,
        queryItems: [URLQueryItem],
        context: NSExtensionContext
    ) {
        var components = URLComponents()
        components.scheme = Self.callbackScheme
        components.host = host
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let callbackURL = components.url else {
            reply(to: context, accepted: false, error: "The app callback URL could not be created.")
            return
        }

        let contextBox = ExtensionContextBox(context)
        context.open(callbackURL) { [weak self, contextBox] accepted in
            guard let self else { return }
            self.reply(
                to: contextBox.value,
                accepted: accepted,
                error: accepted ? nil : "Swifty Download Manager could not be opened."
            )
        }
    }

    private func reply(
        to context: NSExtensionContext,
        accepted: Bool,
        error: String?
    ) {
        var message: [String: Any] = ["accepted": accepted]
        if let error {
            message["error"] = error
        }

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: message]
        context.completeRequest(returningItems: [response])
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
