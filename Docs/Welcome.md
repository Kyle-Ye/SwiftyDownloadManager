# Welcome tour

SDM introduces its main features with a three-page welcome tour: download
management, supported pause/resume and parallel transfers, and browser handoff.
The same tour content runs in a dedicated window on macOS and a sheet on iOS
and iPadOS.

## Reusable package and app content

`Packages/WelcomeKit` contains the reusable SwiftUI tour, its `WelcomePage`
model, navigation, and macOS window presentation. It has no dependency on
SDMCore and contains no SDM copy or brand assets. The host supplies pages,
artwork, and finish/close actions to `WelcomeTourView`.

The application owns its materials under `App/Sources/Features/Welcome/`:

| File | Responsibility |
| --- | --- |
| `SDMWelcomeContent.swift` | Ordered pages and localizable titles and descriptions. Browser text differs between macOS and iOS. |
| `SDMWelcomePageID.swift` | Stable identifiers used to select each page's artwork. |
| `SDMWelcomeArtwork.swift` | Shared responsive banner background and artwork selection. |
| `Artwork/` | SwiftUI illustrations for downloads, connections, and browser handoff, plus shared colors and decorative transfer cards. |
| `SDMWelcomeView.swift` | Connects the SDM page models and artwork to WelcomeKit. |
| `WelcomeLaunchState.swift` | Installation-wide first-presentation policy and persistence. |
| `SDMWelcomeController.swift` | macOS presentation and completion actions. |
| `WelcomeLaunchModifier.swift` | Triggers the macOS controller from the main content's launch task. |

The illustrations are static, decorative SwiftUI shapes and SF Symbols. They
scale with their proposed size, contain no embedded text, and are hidden from
accessibility; the tour's real title and description carry the information.
Static artwork also avoids motion when Reduce Motion is enabled. Colors live
in `SDMWelcomeArtworkStyle`.

`App/Resources/Assets.xcassets/SDMWelcomeLogo.imageset` is a universal image set
for both platforms. Its source PNG is an unchanged copy of the existing
`SDMLockScreenColorLogo@2x.png` brand asset. The original lock-screen image set
is macOS-only. No third-party artwork or tour dependency is bundled. The
existing branding terms in `BRANDING.md` also apply to the welcome materials.

## Updating the tour

1. Add or update a `WelcomePage` in `SDMWelcomeContent.pages`. Each page has a
   unique stable string `id`, a `LocalizedStringResource` title, and a
   `LocalizedStringResource` message. Keep identifiers independent of the
   displayed copy and page order.
2. For a new illustration, add a case to `SDMWelcomePageID` and a view under
   `Artwork/`, then select it in `SDMWelcomeArtwork`. Keep product-specific
   illustrations in the app rather than the package.
3. Check both platform variants. Chrome handoff is available only on macOS;
   Safari handoff is available on all supported platforms. Parallel transfers
   depend on the selected engine and server support, so introductory copy
   must not promise universal acceleration or resumability.
4. Use the welcome view and artwork previews, then check the macOS window
   and an iPhone/iPad sheet, including larger accessibility text sizes.

## First presentation and reopening

`AppStorageKey.hasPresentedWelcome` stores the `hasPresentedWelcome` Boolean
in the app's user defaults. A process-wide claim prevents multiple scenes
from scheduling the automatic tour. The flag is recorded when the tour
appears, so finishing, skipping, or closing it all count as having seen it.
An existing installation without this flag sees the tour once after updating.
Changing page copy or adding a page does not reset the flag.

The welcome tour can be reopened from **Help > Welcome to Swifty Download
Manager…** on macOS or **Settings > About > Welcome to SDM** on iOS. The mobile
presentation is a sheet owned by `MobileContentView`. Manual presentation does
not require resetting stored preferences. Automatic
presentation is suppressed for previews, tests, and the app's store-screenshot
launch mode so those workflows keep their intended starting screen.

To exercise automatic presentation again during development, remove only the
`hasPresentedWelcome` key from the app's defaults or use a fresh app container.
Do not reset download history or the rest of the app preferences.

`bash Scripts/test.sh` includes the WelcomeKit package tests alongside the
existing validation suite. Package tests can also be run independently with
`swift test --package-path Packages/WelcomeKit`.
