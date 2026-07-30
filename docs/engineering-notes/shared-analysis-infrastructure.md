# Shared Analysis Infrastructure

## Scope

AnyUpright shares three internal mechanisms across explicit analysis paths without merging model or effect ownership:

- `AUFxAnalysisTransaction<Request, Result>` for Horizon and Upright request state.
- `AUCoreMLMultiArrayIO` for GeoCalib and ScaleLSD Float32 tensor transport.
- `AUAppleSiliconImageResampler` for GeoCalib and ScaleLSD Metal texture downsampling and tensor packing.
- `AUAnalysisLogger` and `AUMonotonicClock` for analysis diagnostics and timing.
- `AUAnalysisDisplayStatus` and `AUAnalysisStatusTextRenderer` for transient OSC-only analysis feedback.

Warp rendering, Upright reference-line rendering, Stretch OSC diagnostics, model-specific resize layout, output interpretation, fallback decisions, candidate ranking, and parameter writeback remain outside these components.

## FxAnalysis Transactions

Every effect owns a separate strongly typed transaction instance. A transaction atomically stores the request and timeline time before starting host analysis, rejects local or host-busy reentry, calculates the input-time probe through `FxTimingAPI_v4`, and protects result mutation with a generation token.

The first callback with an IOSurface and non-empty pixel bounds claims the request. If image preparation fails, the claim can be relinquished for a later callback. Cleanup distinguishes no produced analysis, a completed analysis without a writeable value, and a produced result. This distinction preserves old state when no frame was usable while allowing a valid empty Upright result to clear old candidate slots.

## Core ML MultiArray IO

`AUCoreMLMultiArrayIO` validates fixed Float32 model descriptions, performs checked shape multiplication, allocates and fills contiguous input arrays, and reads contiguous or strided outputs in logical order. Strided reads derive pointer capacity from the maximum reachable logical stride offset instead of assuming `MLMultiArray.count` describes padded backing storage.

GeoCalib keeps its multi-shape routing and four named outputs. ScaleLSD keeps its fixed `[1, 1, 512, 512]` input and `[1, 9, 256, 256]` output. Both adapters map shared IO failures back to their existing model-specific error types.

## Metal Image Resampling

`AUAppleSiliconImageResampler` is the shared production `MTLTexture -> Float NCHW` path. It delegates high-quality resize and antialiasing to Apple's `MPSImageLanczosScale`; project code implements only the layout geometry and the RGB/grayscale planar tensor packing that MPS does not provide. The scaler uses MPS clamp edge mode so its filter support cannot darken frame boundaries. Lanczos instances are cached by GPU and fixed target slot as recommended by the MPS API, with per-instance encode serialization because Apple permits only one thread to operate on a given `MPSKernel` at a time. The tensor-pack pipeline is cached by GPU.

GeoCalib chooses the nearest fixed model shape and requests aspect-fill center crop with three RGB planes. ScaleLSD retains its model contract by stretching the complete source frame to fixed `512x512` and writing one grayscale plane. Neither adapter changes model routing, output parsing, candidate ranking, or correction geometry.

The production resampler is intentionally Apple Silicon Metal-only. FxAnalysis frames can carry a valid IOSurface while reporting `deviceRegistryID == 0`; analysis texture creation must therefore prefer an exact registered device when available and otherwise bind the IOSurface to `MTLCreateSystemDefaultDevice()`. Command-queue lookup uses the resolved device registry ID, not the host's zero ID. Horizon no longer falls back to Core Image rendering plus Swift CPU preprocessing when this Metal stage fails. Upright also does not substitute CPU Hough candidates when ScaleLSD fails: it relinquishes the current frame claim so another callback can try, and cleanup preserves existing candidates if no callback completes the model path.

## Diagnostics

`AUMonotonicClock` is the single source for analysis and Core ML lifecycle durations. `AUAnalysisLogger` checks a marker file and serializes append operations per process-level logger instance. Horizon and Upright/ScaleLSD retain separate marker and output paths; Upright and ScaleLSD intentionally share one logger and write lock.

These diagnostics do not cover playback rendering or Stretch OSC event logging.

## Analysis Status Overlay

Horizon and Upright register the same hidden, non-animatable, `DONT_SAVE` integer parameter. It carries transient analysis state from the filter instance to its OSC companion; it is not project state and must never affect correction geometry or persisted parameters.

An accepted request first writes `模型加载中`. The typed Core ML lifecycle cache invokes its `sessionReady` callback after session acquisition and immediately before prediction, which changes the state to `画面分析中`. Upright may enter the loading state again when its optional GeoCalib camera-prior session is acquired. Host-busy or local-busy requests do not touch the current state. Start failure, invalid time conversion, normal completion, model failure, and host cleanup all clear the parameter.

The shared renderer creates a cached CoreText texture with a translucent background and composites it in the FxOnScreenControl drawable after the normal OSC geometry. Horizon reuses the existing stable `AnyUprightUprightOSCPlugIn` registration for this status-only pass; Upright adds the status to the same control pass. The status is therefore excluded from final Warp output and tiled render output. `AUAnalysisStatusOverlayLayout` centers the card in the OSC drawable and clips both vertices and texture coordinates to that drawable. The status renderer does not own analysis transitions; each effect remains responsible for mapping its model stages to the shared enum.
