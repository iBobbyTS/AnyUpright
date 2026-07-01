# Quad Render Tile And Source Sampling

Last updated: 2026-06-30 18:11 MDT
Reference commit: d6d426ae4c8d07be95c84686c8931cfbf35b8a69
Observed host versions: macOS 26.5, Motion Studio 6.2, Final Cut Pro 12.2

This note records reusable render-path lessons behind black-edge and edit-preview identity-shift bugs. It does not record product features or implementation choices. Project-specific choices live outside `engineering-notes`; in this repository they are recorded in `../quad-implementation-notes.md`.

For the full coordinate layer inventory, start with `quad-coordinate-layer-contract.md`. This file focuses on render tiles and texture sampling, not OSC interaction.

For Motion preview pan/zoom flicker in full-frame projective or perspective warps, see `fxplug-preview-render-stability.md`.

## Render-Layer Debug Contract

- Render output coordinates should be image-relative even when the host provides padded destination tiles.
- `imagePixelBounds` describes the full logical image. `tilePixelBounds` describes the render request. The Metal texture can include padding implied by the requested tile.
- A shader that samples by logical image pixel must convert that logical pixel into the actual input texture coordinate for the current source tile.
- The shader should receive valid image coordinate min/max and clamp only padded tile coordinates back to the image edge.
- An identity edit preview should be tested as a render invariant: no-plugin output and edit-preview output should align at `dx=0`, `dy=0` before any OSC questions are considered.
- Do not use `pixelTransform` as a first response to a visual offset. Apple defines it as a transform between pixel units and idealized square-pixel image units; whether your preview path needs it depends on which layer is being rendered.
- Pixel aspect ratio and host view correction must be handled as an explicit layer decision. If the symptom is a constant tile-aligned shift rather than aspect stretch, inspect tile origin first.

## Versioned Host Observations

These observations are not Apple API guarantees. They were measured on macOS 26.5 with Motion Studio 6.2 and Final Cut Pro 12.2:

- Destination tile bounds could include padding around the logical image. An observed `3840x2160` render had destination tile values extending outside the image.
- Ignoring the input source tile origin inside the Metal texture produced an edit-preview identity mismatch that measured as a consistent 2 px vertical shift.
- Applying `destinationImage.pixelTransform` or `sourceImage.inversePixelTransform` inside the edit-preview shader double-applied host transforms in the tested path.
- Requesting the same source tile as the destination tile for identity edit preview aligned no-plugin and edit-preview exports at `dx=0`, `dy=0`.

## The 2px Shift Failure

Motion/FCP produced an edit-mode preview that looked uniformly shifted by 2 px vertically compared with the no-plugin image.

Confirmed observations from the debug pass:

- Destination tile bounds could include one pixel of padding around a `3840x2160` image, for example `dstTile={left:-1321 bottom:-481 right:2521 top:1681}`.
- Pixel comparisons showed the plug-in export best aligned with the no-plugin export at `dx=0`, `dy=+2`.
- Table-line projection confirmed horizontal rows were exactly 2 px lower in the plug-in render, while vertical x positions matched.
- The template XML did not contain an obvious 2 px transform, so this was render sampling, not template placement.

Root cause:

- Destination output coordinates had been made image-relative, but input sampling still treated source pixels as if `sourcePixel / imageSize` addressed the source texture.
- With padded source tiles, the Metal texture includes padding around the source image. Ignoring the source tile origin samples from the wrong row/column.
- In edit preview, forcing the full unpadded source image/tile while rendering a padded destination tile made the identity preview no longer truly identity.

Fix pattern:

- Pass input image origin within the texture and input texture size through render state.
- Make texture lookup compute `texturePixel = sourcePixel + inputImageOriginInTexture`, then divide by input texture size.
- Request the destination tile as the source tile in identity edit preview.
- Keep valid image-coordinate clamping for padded output coordinates.

Validation evidence:

- Re-exported fixed preview aligned with no-plugin reference at `dx=0`, `dy=0` across full-inner, table, center, and mid-content ROIs.
- The old export still aligned best at `dx=0`, `dy=+2`, proving the comparison caught the previous failure.
- Regression tests should cover padded output coordinates, input texture origin inside a padded texture, and identity preview source tile selection.

## Previous Wrong Attempts

- Treating the whole padded destination tile as the image frame was wrong; it moved the coordinate system instead of isolating the host padding.
- Fixing only output-coordinate clamping removed black edges but did not fix the residual 2 px shift, because input texture addressing still ignored source tile padding.
- Applying `destinationImage.pixelTransform` or `sourceImage.inversePixelTransform` inside the edit-preview shader double-applied host object/view transforms. The base filter-output preview should stay image-relative in the observed host path.
- Adding feature modes while debugging render identity, such as mirror modes, confused the investigation. Keep product changes separate from coordinate debugging.
