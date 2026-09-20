import Foundation

/// Only encrypted, short-lived handoff data is staged in the App Group.
/// The decryption key travels separately through the app callback.
struct SafariHandoffStore {
    #if os(macOS)
    // macOS authorizes this group using the signing team's identity, including
    // local development builds without a provisioned iOS-style App Group.
    static let groupIdentifier = "VB7MJ8R223.top.kyleye.swifty-download-manager"
    #else
    static let groupIdentifier = "group.top.kyleye.swifty-download-manager"
    #endif
    let directory: URL

    init() throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.groupIdentifier
        ) else { throw BrowserHandoffError.unavailable }
        directory = container.appending(path: "BrowserHandoffs", directoryHint: .isDirectory)
    }

    init(directory: URL) { self.directory = directory }

    func stage(_ data: Data) throws -> BrowserHandoffTicket {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try pruneExpired()
        let ticket = BrowserHandoffTicket(browser: "safari")
        let sealed = try ticket.seal(data)
        #if os(iOS)
        try sealed.write(to: file(for: ticket), options: [.atomic, .completeFileProtection])
        #else
        try sealed.write(to: file(for: ticket), options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file(for: ticket).path)
        return ticket
    }

    func consume(_ ticket: BrowserHandoffTicket) throws -> Data {
        let url = file(for: ticket)
        let attributes = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey])
        guard attributes.isSymbolicLink != true,
              let date = attributes.contentModificationDate, Date.now.timeIntervalSince(date) < BrowserHandoffTicket.lifetime,
              let size = attributes.fileSize, size <= BrowserHandoffTicket.maximumPayloadSize + 28 else {
            try? FileManager.default.removeItem(at: url)
            throw BrowserHandoffError.expired
        }
        defer { try? FileManager.default.removeItem(at: url) }
        return try ticket.open(Data(contentsOf: url))
    }

    func discard(_ ticket: BrowserHandoffTicket) { try? FileManager.default.removeItem(at: file(for: ticket)) }

    func pruneExpired() throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]) where url.pathExtension == "handoff" {
            if let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               Date.now.timeIntervalSince(date) >= BrowserHandoffTicket.lifetime {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func file(for ticket: BrowserHandoffTicket) -> URL {
        directory.appending(path: ticket.id.uuidString.lowercased() + ".handoff")
    }
}
