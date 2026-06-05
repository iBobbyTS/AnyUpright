# Horizon Analysis Writeback Debug

Date: 2026-06-05

## Context

`AnyUpright Horizon Manual` added an `Analyze Horizon` push button that should run FxAnalysis on a representative frame and write the detected rotation into the keyframeable `Rotation` parameter. The visible Motion symptom was that clicking the button showed a short loading state, but `Rotation` stayed at `0` and the image did not change.

The test media was `/Users/ibobby/Documents/test.png`. A standalone command-line check of the fallback Sobel/Hough detector returned approximately `-0.070155 rad`, while manual visual leveling in Motion required about `+10.1 deg`. The algorithm quality was therefore treated as a separate issue; this debug pass focused only on whether FxAnalysis and parameter writeback worked.

## Findings

- Direct parameter writes worked. A temporary test button that wrote `0.1` into the rotation parameter displayed about `5.7 deg` in Motion, proving `FxParameterSettingAPI_v5.setFloatValue` could update the parameter.
- Angle parameter writes behaved as radians in the tested Motion path. Writing `10.1` to the angle parameter clamped to the `45 deg` max, while writing `0.1` displayed about `5.7 deg`. This differs from the FxPlug SDK header comment that says angle writes use degrees.
- Wrapping `cleanupAnalysis` writes in `FxCustomParameterActionAPI_v4.startAction/endAction` did not fix the issue. Removing that wrapper also did not, by itself, fix the issue.
- Changing `Rotation` from an angle slider to a normal float slider did not fix `Analyze Horizon`; the temporary test button still worked, but analysis writeback did not.
- A cleanup sentinel wrote `0.5`, proving `cleanupAnalysis` ran but `analyzeFrame` had not produced any detected value.
- Adding sentinels inside `analyzeFrame` still produced `0.5`, proving the frame callback was not being called.
- Expanding the requested analysis range from `1/600 s` to `1.0 s` changed the output to about `1.09`, where `+1.0` was the temporary sentinel offset. This proved `analyzeFrame` did run once Motion had a large enough requested time range, and the actual detected rotation was about `0.09 rad` in that run.
- The `1.0 s` analysis range made the button take about 6 seconds because Motion analyzed many frames and the detector ran repeatedly.
- Reducing the analysis range to `0.05 s`, skipping work after the first detected frame, and removing sentinel offsets made `Analyze Horizon` write the raw detected result. Motion then wrote about `-0.07`, matching the standalone fallback detector result.

## Root Cause

The original requested analysis range of `1/600 s` was too small for Motion to deliver an analysis frame in this validation setup. FxAnalysis still entered setup and cleanup, which made the issue look like a parameter writeback failure, but the actual missing link was that `analyzeFrame` was not called.

## Current Code Direction

- Keep the explicit FxAnalysis flow for Horizon.
- Request a small but nonzero analysis window of `0.05 s` instead of a single `1/600 s` tick.
- Stop doing expensive detection after the first successful frame result.
- Store render and analysis rotation in radians.
- Write radians back to angle parameters in Motion, based on the observed behavior above.
- Do not wrap analysis cleanup writes in custom parameter action start/end calls.

## Remaining Issue

The writeback path is fixed, but the current horizon detection algorithm is not visually correct for `/Users/ibobby/Documents/test.png`. It writes about `-0.07 rad` while manual leveling needs about `+10.1 deg`. That should be handled as an algorithm/scoring/sign-selection task, not as an FxPlug writeback task.

## Manual Regression Check

1. Build the wrapper app.
2. Reopen or refresh Motion so it loads the current plug-in.
3. Apply `AnyUpright Horizon Manual` to a test image or clip.
4. Click `Analyze Horizon`.
5. Confirm `Rotation` changes from zero without requiring the temporary test button.
6. If testing `/Users/ibobby/Documents/test.png`, expect the current algorithm to write around `-0.07 rad`; this confirms writeback, not algorithm correctness.
