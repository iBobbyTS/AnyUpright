# Core ML Fixed-Shape Model Routing

Last updated: 2026-07-01 16:57 MDT
Reference commit: 23c5dcf48b242464e584b38ea59b2f05653f67f3
Observed versions: macOS 26.5.1 (25F80), Xcode 26.5 (17F42), macOS SDK 26.5 Core ML headers

This note records reusable lessons for validation or production pipelines that use several fixed-shape Core ML models instead of one flexible-shape model.

## Official API Baseline

Core ML exposes model input metadata through the loaded model description. For multi-array inputs, the feature description can expose a multi-array constraint, including the default shape and a detailed shape constraint. The shape constraint can represent enumerated shapes.

That API describes what a single model accepts. It does not define how an application should route preprocessed samples across several separately compiled fixed-shape models, and it does not guarantee that a fixed-shape model can accept a transposed or nearby shape just because the tensor rank is the same.

## Failure Signature

A full validation or batch inference run may pass many samples and then fail when the first image preprocesses to a different fixed tensor shape:

```text
Invalid Core ML input: expected input shape [1, 3, H1, W1], got [1, 3, H2, W2]
```

This failure means the neural conversion may still be correct. The immediate bug is often that the runner loaded one fixed-shape model and treated it as if it covered every preprocessed sample.

## Routing Layers

Keep these layers explicit:

- Source image shape: the original image size and aspect ratio.
- Preprocess target choice: the model input shape selected for that image.
- Preprocessed tensor: the actual `NCHW` or model-specific tensor emitted by preprocessing.
- Model capability: the input shape read from the loaded Core ML model description.
- Inference session map: a dictionary from exact input shape to loaded model session.
- Validation report: per-image accepted/rejected status, timing, and shape used.

The runner should route by the preprocessed tensor's exact input shape, not by the original image size after the fact and not by a best-effort shape inferred from the model filename.

## Diagnostic Checklist

- Count every preprocessed input shape before running the full validation set.
- Log the loaded model's supported input shape from Core ML metadata.
- Refuse duplicate model registrations for the same input shape.
- Fail with a supported-shapes list when a preprocessed input shape has no registered session.
- Smoke-test at least one sample from each observed shape bucket.
- Keep compile/load timing separate from prediction timing, because multi-model routing can hide lazy loads in the first sample of a rare shape.
- If a flexible or enumerated-shape model exists, benchmark it against true fixed-shape packages before replacing the routing map.

## Correct Fix Pattern

- Accept repeated model inputs in validation tools or production configuration.
- Load each model once, inspect its actual input shape, and register it in a shape-keyed router.
- During preprocessing, choose the target shape first and carry that exact shape with the preprocessed tensor.
- At inference, look up the session by the preprocessed shape and run only that exact session.
- Prefer exact-shape errors over silent resizing at the inference boundary. Any resize, crop, or pad decision belongs in preprocessing and should be part of validation.
- For production caches, expire or prewarm sessions per shape so a rare aspect-ratio model does not disturb the hot model for common shapes.

## Versioned Observations

These observations were made with the versions above and should be treated as local validation evidence, not universal Core ML performance guarantees:

- Routing two fixed-shape ML Program sessions by exact preprocessed input shape eliminated the fixed-shape mismatch that appeared late in a 2,000-image validation run.
- The failure was shape routing, not proof that the second fixed-shape ML Program conversion was invalid.
- A rare-shape bucket can be small enough that single-image smoke tests miss it. Full-dataset shape counting caught the gap before broader algorithm debugging was needed.

## Previous Wrong Attempts

- Passing only the most common fixed-shape model to a full validation runner was wrong. It worked until the first image in a less common aspect-ratio bucket reached inference.
- Treating the original image orientation as a sufficient routing key was too indirect. The authoritative key is the exact preprocessed tensor shape.
- Interpreting a fixed-shape mismatch as a neural-layer conversion failure sent the investigation in the wrong direction. First verify the loaded model's accepted shape and the tensor shape actually supplied to prediction.
- Using a flexible-shape or enumerated-shape package as the default fix can be premature. If fixed-shape packages are materially faster in the target environment, a small explicit router may be the correct production design.
