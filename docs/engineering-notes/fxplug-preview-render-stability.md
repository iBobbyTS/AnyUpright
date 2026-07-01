# FxPlug Preview Render Stability For Global Warps

Last updated: 2026-07-01 16:46 MDT
Reference commit: 23c5dcf48b242464e584b38ea59b2f05653f67f3
Observed versions: macOS 26.5.1 (25F80), Motion Creator Studio 6.2 (447036), Xcode 26.5 (17F42), FxPlug SDK package 4.3.4.1.1769575879

This note records transferable lessons for FxPlug effects that apply a global affine, projective, perspective, or upright-style warp and then flicker or jump while the host viewer is panned or zoomed. It does not cover transform sign, reference-line interpretation, Metal texture Y-boundary handling, product workflow, or inspector parameter design.

For guided reference-line geometry, see `guided-upright-projective-geometry.md`. For shader/image/texture boundary matrices, see `fxplug-metal-render-boundary-matrices.md`.

## Official API Baseline

The FxPlug SDK headers define the following contracts:

- `FxImageTile.tilePixelBounds` is the pixel bounds of the tile passed to the effect.
- `FxImageTile.imagePixelBounds` is the pixel bounds of the entire image associated with that tile.
- `FxImageTile.pixelTransform` converts between pixel units and idealized 100% square-pixel image units; `inversePixelTransform` is its inverse.
- `sourceTileRect` must return the input tile needed to render the requested output tile.
- `renderDestinationImage` receives the destination tile and the source tiles requested through `sourceTileRect`; render code must not fetch parameters there.
- `kFxPropertyKey_NeedsFullBuffer` tells the host the effect needs the entire image and cannot tile its rendering. The header warns that this has a significant performance cost.
- `kFxPropertyKey_PixelTransformSupport` declares the pixel-transform class the renderer supports. The default is `kFxPixelTransform_ScaleTranslate`; `kFxPixelTransform_Full` means the effect handles full perspective host pixel transforms.

The headers do not promise that Motion preview pan/zoom requests will expose the original media dimensions through `imagePixelBounds`, nor do they describe the one-pixel preview-boundary rounding behavior observed below.

## Versioned Observations

These observations were measured on the versions above and should be treated as host behavior, not universal API guarantees.

- Motion preview pan/zoom can drive partial destination tiles for an effect whose visible output depends on a full-frame projective correction. In the observed failure, the source image bounds, source tile, destination image bounds, output-to-source matrix, and source texture size stayed stable while the destination tile bottom changed across frames. The viewer appeared to jump vertically during pan/zoom.
- Enabling full-buffer rendering for that global warp changed the same preview path from partial destination tiles to full-buffer requests, removing one class of viewer-position flicker.
- A second flicker source remained when the correction matrix was initialized from preview-sized `imagePixelBounds`. A 100% source that should remain `5712x4284` could be inferred as `5718x4284`, `5718x4290`, or `5716x4288` from a clipped preview request before later requests corrected it. That one-frame stable-size jump is enough to move a global warp visibly.
- Directly computing `imagePixelBounds.width / pixelTransform.scale` can over-count by one preview pixel per axis. In one observed Motion 6.2 request, bounds width `913`, scale `0.159664`, and transform translation near the preview bounds center over-counted the idealized width until the one-pixel rounded edge was removed.
- Small proxy or thumbnail preview requests can still carry enough `pixelTransform` information to recover the real 100% idealized size, but they should not replace a larger trusted cached size.
- Existing host instances can cache effect properties and stale plug-in identities. After changing `NeedsFullBuffer` or pixel-transform support, re-add the effect and verify the host is launching the intended build before judging render math.

## Render Layers

Keep these layers separate when diagnosing preview flicker:

- Host request layer: `imagePixelBounds`, `tilePixelBounds`, `pixelTransform`, Metal texture size, and tile origin. These can vary with viewer zoom, pan, proxy rendering, and host preview caching.
- Stable correction layer: the image size and coordinate frame in which a global warp is solved. This should be the stable 100% idealized image size, not whichever preview tile happened to initialize first.
- Current tile sampling layer: mapping from the current destination tile to the current source tile texture. This layer must respect the source tile origin and texture size, but it should not redefine the global correction frame.

For a global warp, the safe model is:

1. Recover or cache a stable correction input/output size.
2. Build the correction matrix in that stable frame.
3. Adapt the stable correction matrix to the current render request's destination and source tile dimensions.
4. Sample the source texture using the current source tile origin.

## Diagnostic Checklist

- Add temporary, flag-controlled render logging for source and destination image bounds, tile bounds, Metal texture sizes, pixel transforms, stable correction sizes, output-to-source matrix, and output-corner sample mappings.
- Trigger the host viewer motion that reproduces the issue, such as pan or zoom. Parameter drag bugs and viewer pan/zoom bugs can look similar but exercise different host requests.
- First classify the unstable value:
  - If only destination tile bounds move while the correction matrix and stable size stay fixed, suspect a partial-tile render path for a full-frame effect.
  - If the correction matrix or stable size changes between adjacent preview requests, suspect preview-boundary size recovery.
  - If only the displayed OSC overlay moves while filter output is stable, debug OSC canvas mapping instead of render sampling.
  - If offline CPU geometry is stable and matches the logged project matrix but live Metal is flipped or inverted, suspect image-to-texture or output-coordinate render boundaries instead of preview-size recovery.
- Check whether the effect actually needs full-buffer rendering. Use it only for global operations that cannot produce stable output from independent tiles.
- Confirm pixel-transform support is not over-declared. Do not advertise full perspective host-transform support unless render code implements that support.
- After changing static properties or registration, restart/re-add the effect and verify that only the intended plug-in build is registered.
- Add deterministic geometry tests for observed preview-boundary cases, including one-pixel rounded extents and cached-size merge behavior.

## Correct Fix Pattern

- For a full-frame projective or perspective warp that cannot be evaluated independently per destination tile, set `NeedsFullBuffer` for that effect.
- Keep `PixelTransformSupport` at `ScaleTranslate` unless the renderer explicitly handles full perspective host pixel transforms.
- Prefer stable source-size APIs or host object/input size APIs when available. Use `imagePixelBounds` plus `pixelTransform` only as a fallback.
- When deriving idealized size from preview bounds, compare the direct extent with `extent - 1` in pixel-transform units. If the trimmed extent is closer to an integer idealized size, treat the preview edge as host rounding.
- Also detect the half-pixel center-rounding case when pixel-transform translation is about half a pixel away from the preview bounds center.
- Cache the stable idealized size and merge conservatively:
  - Reject zero or non-finite candidates.
  - Do not replace a larger trusted size with a much smaller clipped preview candidate.
  - For near-equal candidates, prefer the smaller rounded size when it removes preview-edge over-counting.
- Compute the correction in the stable frame, then compose it with current request source/output scaling so preview, export, and proxy requests share one correction model.

## Previous Wrong Attempts

- Treating viewer flicker as an auto-crop-only issue was wrong. The issue reproduced with crop disabled because the unstable layer was the host preview render request.
- Applying the correction directly in the current preview request's image bounds was wrong for global warps. The first request could initialize a slightly wrong frame, then later requests would correct it and create a visible jump.
- Advertising `kFxPixelTransform_Full` without implementing full perspective host pixel transforms was wrong. It invites host requests the renderer has not proven it can handle.
- Masking samples against the clipped source texture coverage looked plausible when logs showed changing source tile coverage, but it did not fix the flicker and introduced a zoom/scale regression. Tile texture coverage is a sampling concern; it should not be used to redefine the global correction frame without a narrower repro.
- Testing an already-applied effect after changing full-buffer behavior produced misleading results because the host could keep old properties or old plug-in identity alive.
- Leaving verbose render logging enabled during interactive validation is risky. Logging should be flag-controlled and absent during final subjective flicker checks.
- Reusing this flicker checklist for every wrong-looking projective result is too broad. A stable but vertically flipped render belongs to render-boundary debugging, and a stable but geometrically wrong guided correction belongs to reference-line solver debugging.
