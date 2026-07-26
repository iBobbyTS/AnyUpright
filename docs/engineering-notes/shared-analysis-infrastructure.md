# Shared Analysis Infrastructure

## Scope

AnyUpright shares three internal mechanisms across explicit analysis paths without merging model or effect ownership:

- `AUFxAnalysisTransaction<Request, Result>` for Horizon and Upright request state.
- `AUCoreMLMultiArrayIO` for GeoCalib and ScaleLSD Float32 tensor transport.
- `AUAnalysisLogger` and `AUMonotonicClock` for analysis diagnostics and timing.

Warp rendering, Upright reference-line rendering, Stretch OSC diagnostics, model preprocessing, output interpretation, fallback decisions, candidate ranking, and parameter writeback remain outside these components.

## FxAnalysis Transactions

Every effect owns a separate strongly typed transaction instance. A transaction atomically stores the request and timeline time before starting host analysis, rejects local or host-busy reentry, calculates the input-time probe through `FxTimingAPI_v4`, and protects result mutation with a generation token.

The first callback with an IOSurface and non-empty pixel bounds claims the request. If image preparation fails, the claim can be relinquished for a later callback. Cleanup distinguishes no produced analysis, a completed analysis without a writeable value, and a produced result. This distinction preserves old state when no frame was usable while allowing a valid empty Upright result to clear old candidate slots.

## Core ML MultiArray IO

`AUCoreMLMultiArrayIO` validates fixed Float32 model descriptions, performs checked shape multiplication, allocates and fills contiguous input arrays, and reads contiguous or strided outputs in logical order. Strided reads derive pointer capacity from the maximum reachable logical stride offset instead of assuming `MLMultiArray.count` describes padded backing storage.

GeoCalib keeps its multi-shape routing and four named outputs. ScaleLSD keeps its fixed `[1, 1, 512, 512]` input and `[1, 9, 256, 256]` output. Both adapters map shared IO failures back to their existing model-specific error types.

## Diagnostics

`AUMonotonicClock` is the single source for analysis and Core ML lifecycle durations. `AUAnalysisLogger` checks a marker file and serializes append operations per process-level logger instance. Horizon and Upright/ScaleLSD retain separate marker and output paths; Upright and ScaleLSD intentionally share one logger and write lock.

These diagnostics do not cover playback rendering or Stretch OSC event logging.
