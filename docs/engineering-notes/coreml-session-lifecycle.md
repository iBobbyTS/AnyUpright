# Core ML Session Lifecycle

Last updated: 2026-07-25

This note defines the plugin-process ownership and retention contract for Core ML sessions used by AnyUpright.

## Ownership Boundary

`AUCoreMLSessionLifecycleCache<Key, Session>` owns only the reusable lifecycle algorithm:

- serialized cache state and cold-session creation
- asynchronous plugin-add prewarming
- configurable retention deadlines
- generation-protected expiry timers
- load, prediction, and total timing

Each model family owns a separate strongly typed facade and cache instance. GeoCalib keys sessions by exact fixed input shape. ScaleLSD uses the internal `.fixed512` key. The two model families never share sessions, keys, configuration, timers, or retention state.

The lifecycle component does not own preprocessing, model URL selection, Core ML output parsing, candidate ranking, transform solving, fallback behavior, or UI state. Command-line exporters continue to create explicit sessions and reuse them for the process lifetime.

## Retention Policy

The plugin defaults to the configurable `AUCoreMLSessionRetentionPolicy.analysisDefault` policy:

- plugin added or model prewarm requested: retain for 15 seconds
- first analysis in a new window: retain for 30 seconds
- another analysis inside that 30-second window: retain for 60 seconds

A new event can extend an existing deadline but cannot shorten it. When a session is unloaded, its analysis-window state is reset. GeoCalib applies this state independently to every input shape; ScaleLSD has one state for its fixed 512x512 model.

## Concurrency Contract

All cache state is protected by a private serial queue. Acquiring a session and extending its analysis deadline happen atomically, so concurrent requests for the same cold key perform one load and share the resulting session.

Prediction runs outside the state queue. The analysis closure holds a local strong session reference, allowing an expiry timer to remove the cached reference without interrupting an in-flight prediction. Every timer reschedule increments a generation; an older timer cannot unload a session whose deadline was extended later.

FxAnalysis may deliver several frames for the shared Horizon/Upright/Inner Stretch two-sample probe range. `AUFxAnalysisTransaction` atomically claims only the first frame that can enter an effect's analysis path, so one user action produces one lifecycle analysis event, including when the model result is rejected. A callback whose image cannot be prepared releases the claim for a later callback; this is frame availability handling, not a model retry policy.

Plugin-add prewarming returns immediately and runs on a dedicated queue. A newly loaded session is warmed once. A cache hit does not run warm-up again. Loader failures are not cached and can be retried; prediction failures propagate without clearing a valid cached session or changing model-specific fallback decisions.

Replacing a model facade configuration creates a new lifecycle cache. New requests use the new cache, while requests already running against the old cache finish through their local references. Destroying an old cache cancels its pending timers.

## Logging Contract

The lifecycle logger is invoked outside the state queue and must be a process-level static logger, never a closure retaining an effect instance. Generic lifecycle messages include:

- model/cache label and key
- cache hit status
- session load milliseconds
- prediction milliseconds
- total milliseconds
- retention seconds and analysis count inside the window
- expiry and load/warm/prediction failures

Model adapters may emit their existing stage logs in addition to these fields. Logging must not alter fallback behavior or analysis results.
