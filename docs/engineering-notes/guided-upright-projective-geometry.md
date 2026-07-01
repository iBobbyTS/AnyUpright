# Guided Upright Projective Geometry

Last updated: 2026-07-01 16:46 MDT
Reference commit: 23c5dcf48b242464e584b38ea59b2f05653f67f3
Observed versions: macOS 26.5.1 (25F80), Motion Creator Studio 6.2 (447036), Xcode 26.5 (17F42), FxPlug SDK package 4.3.4.1.1769575879

This note records transferable geometry lessons for guided upright or perspective-correction tools that let a user draw reference lines which should become vertical or horizontal after correction. It is not a product feature description. Current product behavior and parameter names should live in project implementation docs.

For coordinate-layer and Y-axis rules, read `quad-coordinate-layer-contract.md` and `y-axis-coordinate-conventions.md` first. This file focuses on the geometric contract once reference lines are already expressed in one consistent image/output coordinate system.

## Official API Baseline

The FxPlug SDK does not define a guided-upright model. Its relevant baseline is only that effects receive image tiles, onscreen controls can persist parameters, and render callbacks receive the state needed to draw a frame. The line-to-transform contract belongs to the plug-in or application.

External product references such as guided upright tools commonly describe user-drawn lines as references that should become vertical or horizontal. That UX statement is not a matrix algorithm. A renderer still has to decide:

- which coordinate system stores guide endpoints;
- whether a guide is a finite segment or a sample of an infinite scene line;
- which degrees of freedom are allowed for a mode such as vertical-only correction;
- which invariants prevent visually adding rotation or shear.

## Reference-Line Contract

A guided reference line should be treated as a source-image scene line. The correction target is:

```text
source line -> source-to-output transform -> corrected output line
```

For a vertical guide, the corrected output line should have near-zero `dx`. For a horizontal guide, it should have near-zero `dy`.

Do not interpret the guides as target angles for the new output frame border. A line drawn on the source image says what should happen to that source line after rectification; it does not by itself say the output image's left and right frame edges should copy the line angles.

## Geometry Layers

Use separate layers when designing or debugging the solver:

- Stored guide layer: normalized object or canvas parameters persisted by the host.
- Image-reference layer: source image pixels or normalized image coordinates after all storage Y-axis conversion.
- Stable correction layer: the image size used to solve the projective correction.
- Source-to-output geometry layer: the inverse of the render sampler's output-to-source matrix, used to evaluate whether guides become vertical or horizontal.
- Render adaptation layer: scaling or cropping that adapts the stable correction to the current host render request.

The solver should run in the image-reference and stable correction layers. It should not read host viewer zoom, current render tile, texture origin, or OSC drawable dimensions.

## Versioned Observations

These observations were measured on the versions above and should be treated as validation lessons, not FxPlug API guarantees:

- A live Motion render can make a correct solver look wrong when the host is still using a stale effect instance or stale XPC service. Verify host freshness before changing the line solver.
- Endpoint-only validation can pass while the user's intended visible edge still looks wrong. Check the actual source feature after render, not just the persisted guide segment.
- A direct four-point mapping built from two guide segments can pass guide-line verticality checks while introducing scanline shear. Include a scanline-preservation regression for vertical-only modes.

## Vertical-Only Guided Model

For two vertical source reference lines, a robust vertical-only model is based on their vertical vanishing point:

1. Convert both stored guide segments into image-space lines.
2. Intersect the supporting lines to obtain the vertical vanishing point.
3. Build a projective transform that sends that vanishing point to vertical infinity.
4. Anchor the correction around an explicit horizontal line, commonly the image centerline.
5. Preserve horizontal scanlines as horizontal in the source-to-output transform.

This model lets off-center guide pairs converge to a vanishing point that is not on the image center axis. A centered keystone parameter cannot represent that geometry without leaving residual tilt.

For a vertical-only correction, avoid consuming a residual rotation value. If the reference lines become more vertical only because the whole image rotates, the mode is mixing concerns. Reserve rotation for a mode that explicitly owns it.

## Validation Surfaces

Checking only the fitted guide endpoints is insufficient. A geometry regression should include:

- each selected guide line transformed through the source-to-output matrix and measured for near-zero output `dx`;
- horizontal source scanlines transformed through the same matrix and measured for near-zero output `dy` in vertical-only mode;
- stable-size adaptation checks that the same normalized output samples map consistently across preview sizes;
- render-path checks that the matrix handed to the shader has not been reinterpreted across an image-to-texture boundary;
- visual validation on the actual source feature the user used as a guide, not only the persisted endpoint coordinates.

The source feature check matters because a short drawn segment may lie near a visible edge without representing the full edge the user expects to straighten.

## Diagnostic Checklist

- Log stored guide endpoints and explicitly label their coordinate space.
- Convert guides to image-space lines in a testable helper before estimating any matrix.
- Evaluate both the source-to-output and output-to-source matrices with representative points.
- Compute guide-line deviation after correction, not only the sign or magnitude of a scalar perspective parameter.
- Sample horizontal or vertical scanlines to detect unintended rotation or shear.
- Compare the stable correction matrix against the current render-request-adapted matrix separately.
- If Motion or another host still looks wrong while offline geometry is correct, inspect the render boundary, stale plug-in identity, or host state before changing the solver.

## Correct Fix Pattern

- Keep guide interpretation independent from render tiles and host preview zoom.
- Store or recompute a matrix for guide configurations that cannot be represented by a centered scalar keystone.
- For vertical-only guided correction, solve from the vertical vanishing point and keep scanlines horizontal.
- Treat scalar centered perspective parameters as fallback or simpler-path state, not as the only representation of guided geometry.
- Add regression tests for both guide straightening and scanline preservation.
- Run an offline render or deterministic sample calculation before judging a live host result, then verify the live host is loading the intended build.

## Previous Wrong Attempts

- Treating the two guide segments as if they defined the new output frame side angles was wrong. The guides are source lines that should become vertical or horizontal after correction.
- Reversing a scalar perspective sign without checking the transformed guide lines was wrong. The sign may appear plausible in one aspect ratio or coordinate convention while still failing the source-line contract.
- Using one centered vertical keystone for off-center guide pairs was under-expressive. It reduced deviation but left both corrected lines tilted because the real vanishing point was off axis.
- Deriving a four-point homography directly from two guide segments over-constrained the problem. It can make the finite guide segments vertical while introducing visible scanline shear or rotation.
- Verifying only persisted guide endpoints produced false confidence. The visible source edge and the corrected scanline behavior must also be checked.
