# SDM App Icon

The icon represents SDM's segmented download engine: three parallel transfer
streams converge into one download arrow and finish in a receiving tray.

## Files

- `SDM-icon-foreground.png` is the 1024 × 1024 transparent source artwork.
- `SDM-icon-preview.png` is the 256 × 256 default appearance compiled by Xcode.
- `../../App/Resources/AppIcon.icon` is the macOS-only Icon Composer document
  consumed by Xcode.

## Icon Composer settings

- Background: adaptive `System Light` (neutral light surface in Default,
  graphite surface in Dark)
- Group: `Download Mark`
- Layer: `Parallel Streams and Tray`
- Specular: on
- Blur: off
- Translucency: off
- Shadow: neutral, 50%
- Platform: macOS only

The default, dark, and mono appearances use Icon Composer's automatic color
adaptation.

## Generation prompt

```text
Use case: logo-brand
Asset type: macOS application icon foreground concept for Apple Icon Composer
Primary request: Create an original symbol for “Swifty Download Manager (SDM)”, a native macOS multi-connection download manager. Show three sleek parallel data streams converging into one bold downward download arrow, ending just above a compact receiving tray. The symbol should communicate speed, segmented parallel transfers, reliability, and completion.
Scene/backdrop: perfectly flat solid #00ff00 chroma-key background for local removal
Style/medium: premium vector-friendly 3D app icon foreground, simple geometric forms, subtle depth, precise Apple-platform polish; crisp opaque subject
Composition/framing: centered, front-facing with a very slight isometric depth; strong silhouette; generous padding; readable at 16 px; the complete symbol occupies about 72% of the square canvas
Color palette: electric cyan and vivid system blue with small deep-navy inner faces; restrained highlights
Materials/textures: smooth satin enamel with controlled glossy edge highlights; no glass, no translucency
Constraints: background must be exactly one uniform #00ff00 color with no shadows, gradients, texture, floor plane, reflections, or lighting variation; subject separated cleanly from background; no cast shadow; no contact shadow; no text; no letters; no rounded-square app tile; no watermark; do not use #00ff00 anywhere in the subject
Avoid: speedometer, cloud, globe, lightning bolt, paper document, brand marks, intricate details, thin lines, photorealism, mockup context
```

The built-in image generation path produced the concept. The chroma-key
background was removed locally, with a one-pixel edge contraction to eliminate
the green fringe before importing the foreground into Icon Composer.
