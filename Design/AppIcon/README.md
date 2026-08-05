# SDM App Icon

The icon turns SDM's segmented transfer engine into a single download mark.
Six precise blocks form two parallel data lanes that converge into one arrow,
with a compact receiving tray below. Swift orange keeps the mark closely tied
to the app's native Swift identity while the split geometry remains legible at
small sizes.

## Files

- `SDM-icon-source.svg` is the editable 1024 × 1024 vector source.
- `SDM-icon-foreground.png` is the 1024 × 1024 transparent Icon Composer layer.
- `SDM-icon-preview.png` is the 256 × 256 appearance compiled by Xcode.
- `../../App/Resources/AppIcon.icon` is the shared iOS and macOS Icon Composer
  document consumed by Xcode.

## Construction

- Tile: restrained Swift-orange gradient centered on `#F05138`
- Mark: warm white `#FFFDFC`
- Layout: bilateral symmetry with a 16 px center seam in the converging arrow
- Rendering: vector geometry with one restrained glyph shadow; no generated
  texture, bevel, glass, or 3D extrusion
- App accent: `AccentColor.colorset` uses solid `#F05138`

## Icon Composer settings

- Background: adaptive `System Light`
- Group: `Download Mark`
- Layer: `Segmented Swift Download`
- Blur: off
- Translucency: off
- Shadow: neutral, 50%
- Platforms: iOS and macOS

## Generation and refinement prompt

The built-in image generation tool was used once to refine the approved raster
reference and establish the optical proportions. The production artwork was
then rebuilt deterministically as SVG.

```text
Use case: logo-brand
Asset type: polished iOS and macOS app icon concept for a Swift download manager
Input image: approved segmented-download icon; preserve the core direction
Primary request: professionally redraw the same six-part segmented download
symbol with perfect bilateral symmetry, consistent spacing and corner radii,
a slightly larger arrow, a wider receiving tray, and Swift orange #F05138.
Style: iconic Apple-platform vector design; minimal, precise and readable from
16–1024 px
Constraints: preserve the six segments and tray; no letters, bird, brackets,
extra lines, 3D extrusion, bevel, glass, texture, busy gradient, or watermark
```
