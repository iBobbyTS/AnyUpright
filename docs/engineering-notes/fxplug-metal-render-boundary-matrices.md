# FxPlug Metal Render Boundary Matrices

Last updated: 2026-07-01 16:46 MDT
Reference commit: 23c5dcf48b242464e584b38ea59b2f05653f67f3
Observed versions: macOS 26.5.1 (25F80), Motion Creator Studio 6.2 (447036), Xcode 26.5 (17F42), FxPlug SDK package 4.3.4.1.1769575879

This note records transferable render-boundary lessons for FxPlug Metal effects that pass projective or affine matrices from Swift or Objective-C into a shader. It focuses on avoiding scattered Y-axis flips and mismatched image-to-texture semantics.

For host preview stability, see `fxplug-preview-render-stability.md`. For general Y-axis conventions, see `y-axis-coordinate-conventions.md`.

## Official API Baseline

The FxPlug SDK headers define useful render facts:

- `FxImageTile.imagePixelBounds` describes the logical image associated with a tile.
- `FxImageTile.tilePixelBounds` describes the tile supplied to the effect.
- `FxImageTile.pixelTransform` and `inversePixelTransform` describe pixel-unit to idealized-image-unit transforms.
- `sourceTileRect` requests which input tile the render will need.
- `renderDestinationImage` receives the destination tile and source tiles chosen for that render.

The headers do not define a plug-in's internal image coordinate convention, do not say that source image pixels and Metal texture pixels have the same origin, and do not define where a projective matrix should absorb host tile padding or Y-axis flips.

## Matrix Semantic Layers

Keep these matrices conceptually separate:

- Project geometry matrix: maps corrected output image coordinates to source image coordinates, or its inverse. This matrix should use the plug-in's explicit image coordinate convention.
- Render request adaptation matrix: maps current preview/export output coordinates into the stable correction frame and back to the current source frame.
- Source-image-to-input-texture matrix: maps source image pixels into the current `FxImageTile` Metal texture, including tile origin and any texture Y boundary.
- Output-display boundary matrix: maps the fragment's output coordinate convention into the image convention expected by the project geometry matrix.
- Selection or overlay helper matrix: maps edit-preview output coordinates into a selection rectangle or dimming mask and must cross the same output boundary as the main image sampling path.

Only the composed shader matrix should know about the current tile texture. The project geometry matrix should remain reusable by CPU tests and offline renderers.

## Correct Composition Pattern

Build the shader-facing sampler matrix as:

```text
output display coordinate
  -> output image coordinate boundary
  -> output-to-source project geometry
  -> source image to input texture boundary
  -> input texture pixel
```

Then the shader can evaluate one matrix and treat the result as a texture pixel:

```text
texturePixel = outputToTexture * float3(outputCoordinate, 1)
uv = texturePixel / inputTextureSize
```

This keeps the fragment shader from having one Y flip before matrix evaluation and another Y flip before texture sampling. It also makes CPU tests possible: a boundary-adjusted matrix should equal the old shader's two explicit boundary conversions at representative points.

## Coverage And Clamping

Sampling and image coverage are related but not identical:

- Texture UV calculation should address the current Metal texture.
- Source image coverage should still be evaluated in source image pixels, not texture pixels.
- If the shader receives texture pixels, convert them back to source image pixels for coverage and edge antialiasing.
- Clamp only after converting to texture UV; do not use clamping to hide a wrong tile-origin or Y-boundary conversion.

## Diagnostic Checklist

- Log image bounds, tile bounds, texture size, texture origin, project geometry matrix, and final shader matrix separately.
- Label whether a logged matrix maps to source image pixels or texture pixels.
- Build a small gradient or coordinate-color shader to confirm the fragment input coordinate orientation before adding an output flip.
- Compare an offline CPU render against the live Metal path using the same project geometry matrix.
- Test padded source tiles where the image origin inside the texture is not `(0, 0)`.
- Test a non-identity homography and a selection/dimming matrix, because the main image and edit-preview mask can cross the same output boundary in different code paths.

## Versioned Observations

These observations were measured on the versions above and should be treated as host behavior, not universal API guarantees:

- In the tested Motion Metal path, the fragment input output coordinate already behaved as image-style Y-down for the plug-in's render vertices. Adding a second output-coordinate flip before matrix evaluation inverted the corrected image after the projective geometry had otherwise been solved.
- The input texture boundary still needed an explicit source-image-to-texture conversion. Sampling the texture as if source image pixels and texture pixels shared the same Y origin produced an orientation mismatch in the live host while the offline CPU geometry was correct.
- Moving both former shader-side Y conversions into a Swift-side boundary-adjusted matrix preserved the verified Motion render while making the Metal shader sample texture pixels directly.

## Correct Fix Pattern

- Define the project geometry matrix in source/output image pixels and keep it independent from Metal texture layout.
- Compose render-boundary matrices outside the shader when practical.
- Pass a single shader-facing matrix with a precise semantic name, such as output-to-texture, even if the legacy field name is broader.
- Keep edit-preview or selection matrices crossing the same output boundary as the main sampler.
- Add tests that compare the new boundary-adjusted matrix against the old explicit conversion behavior before deleting shader-side flips.
- If a live host result differs from an offline render using the same geometry, verify shader matrix semantics and host plug-in freshness before changing the solver.

## Previous Wrong Attempts

- Adding isolated `height - y` conversions inside the shader made the render appear correct temporarily but obscured whether the project matrix mapped to source image pixels or texture pixels.
- Treating the input texture Y boundary as part of the project geometry was wrong. The same geometry matrix should be valid for offline CPU rendering and for host Metal rendering.
- Feeding a matrix labeled as output-to-source into a shader after it had become output-to-texture was confusing. Debug logs and state names need to reflect the semantic change, or log both matrices.
- Applying a final output-coordinate flip as a display compensation was not a production model. It hid that the matrix-input coordinate boundary had not been named.
- Using source-texture coverage as a fix for host-preview instability was wrong for this class of bug. Coverage is a sampling mask; it should not redefine the correction frame or tile adaptation.
