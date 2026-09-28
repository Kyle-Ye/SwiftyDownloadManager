#if os(macOS)
import AppKit
#endif
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling, @unchecked Sendable {
    private static let callbackScheme = "swifty-download-manager"
    #if os(macOS)
    private static let containingApplicationIdentifier =
        "top.kyleye.swifty-download-manager-app"
    private static let callbackNotificationName = Notification.Name(
        "top.kyleye.swifty-download-manager.browser-callback"
    )
    #endif

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

        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            let ticket = try SafariHandoffStore().stage(data)
            openCallbackURL(ticket.callbackURL, context: context)
        } catch {
            reply(to: context, accepted: false, error: "The browser session could not be handed to SDM.")
        }
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

        openCallbackURL(callbackURL, context: context)
    }

    private func openCallbackURL(_ callbackURL: URL, context: NSExtensionContext) {
        #if os(macOS)
        if !NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.containingApplicationIdentifier
        ).isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                Self.callbackNotificationName,
                object: callbackURL.absoluteString,
                userInfo: nil,
                deliverImmediately: true
            )
            reply(to: context, accepted: true, error: nil)
            return
        }
        #endif

        let contextBox = ExtensionContextBox(context)
        context.open(callbackURL) { [weak self, contextBox] accepted in
            guard let self else { return }
            if !accepted, let ticket = BrowserHandoffTicket(callbackURL: callbackURL) {
                try? SafariHandoffStore().discard(ticket)
            }
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

}
