import Foundation

/// One step in a welcome tour. Artwork is supplied separately by the hosting app.
public struct WelcomePage: Identifiable, Sendable {
    /// A stable, unique identifier, also usable to select the page's artwork.
    public let id: String
    public let title: LocalizedStringResource
    public let message: LocalizedStringResource

    public init(id: String, title: LocalizedStringResource, message: LocalizedStringResource) {
        self.id = id
        self.title = title
        self.message = message
    }
}
