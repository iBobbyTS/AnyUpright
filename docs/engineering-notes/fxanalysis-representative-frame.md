# FxAnalysis Representative Frame

## Scope

Horizon and Upright use the same narrow time-range policy but keep separate request transactions. Stretch is intentionally unchanged.

## Time Domains

The Analyze button captures `FxCustomParameterActionAPI_v4.currentTime()` once. That value is timeline time and remains the parameter writeback time. `desiredAnalysisTimeRange` converts it to input time with `FxTimingAPI_v4.inputTime(_:fromTimelineTime:)`; an input callback time is never written directly to a parameter.

The input probe is aligned to the input sampling grid relative to `inputTimeRange.start` and has this duration:

```swift
max(0.05 seconds, 2 * sampleDuration)
```

`sampleDuration` is the native input sample interval reported by `FxTimingAPI_v4`, not the timeline frame rate. Invalid sample duration falls back to 0.05 seconds. The range is clipped at the input head and tail, so a short source or the final sample may produce a shorter request.

## Request And Frame State

Before starting, each effect checks both its local pending request and the host's requested/started state. It saves request metadata before calling `startForwardAnalysis`, because the host may synchronously ask for the desired range. Missing APIs, invalid time conversion, and start errors clear only transient request state.

Every callback increments a diagnostic count. A frame needs an IOSurface and non-empty pixel bounds before it may claim the request. The first claimant runs detection; later callbacks return without inference. If that claimant cannot produce any readable/preprocessed image through the primary or fallback path, it releases the claim so the next callback in the two-sample probe can take over.

Horizon rejected/no-detection outcomes are completed analyses but do not write Rotation. Upright records a produced result even when it contains zero candidates, allowing a valid empty result to clear old candidates. If no callback can be prepared, cleanup preserves the existing Upright candidate and selection parameters.
