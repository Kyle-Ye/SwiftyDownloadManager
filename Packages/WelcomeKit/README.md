# WelcomeKit

A small, dependency-free SwiftUI welcome tour for macOS 14+ and iOS 17+.
Each page pairs a decorative banner with a localized heading and description.
The package owns layout and paging; the app owns its content, presentation, and
first-launch state.

```swift
import SwiftUI
import WelcomeKit

let pages = [
    WelcomePage(
        id: "welcome",
        title: "Welcome to My App",
        message: "A brief introduction to what you can do."
    ),
]

WelcomeTourView(
    pages: pages,
    artwork: { page in
        MyWelcomeArtwork(pageID: page.id)
    },
    onFinish: finishWelcome,
    onClose: dismissWelcome
)
```

Use stable, unique page IDs. Titles and messages are `LocalizedStringResource`
values resolved by the host's bundle; the built-in buttons and page count ship
with English and Simplified Chinese translations. The artwork closure keeps
product-specific images, symbols, and illustration models in the app. Artwork
is decorative and hidden from VoiceOver, so all essential information belongs
in the title and message.

The banner is approximately 16:10, with its height capped at 320 points and
reduced in short presentations. Artwork should adapt to its proposed size.
Text and artwork scroll while navigation stays visible. System text styles,
appearance, accent color, Reduce Motion, and an accessible page count are
respected. Back and Continue navigate; Get Started calls `onFinish`. An empty
tour still provides a safe Get Started/Close path. Replacing pages preserves
the current index where possible and clamps it when pages are removed.

## macOS

Retain one `WelcomeWindowController` in the app's presentation coordinator:

```swift
controller.present(title: "Welcome to My App", content: tour) {
    // The window has closed, including Command-W or controller.close().
}
```

The controller creates one centered, nonmodal window at normal level, with
a hidden title bar and a preferred 640 × 650 point size constrained to the
screen. Restoration is disabled. Repeated `present` calls bring the existing
tour forward without resetting its page or replacing its callbacks. `close()`
disposes of the content and calls the supplied close handler once. Capture
the controller or its owner weakly from hosted content and close callbacks.
Return activates the primary button; Escape closes through `onClose`.

## iOS

Present `WelcomeTourView` in a sheet or full-screen cover owned by the app.
The view does not require an AppKit controller or reach into UIKit. The host
handles interactive sheet dismissal in its own `onDismiss` callback, and
decides whether dismissal or only finishing counts as having seen the tour.
Honor safe areas when presenting it, including the home indicator.

## Validation

```sh
swift test --package-path Packages/WelcomeKit
```

Paging tests cover forward/backward bounds, finishing, zero/one-page tours,
and changing the page count while the tour is open. The app's platform builds
validate integration and resource bundling.
