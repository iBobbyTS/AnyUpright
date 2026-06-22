#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="${TMPDIR:-/tmp}/AnyUprightSwiftGeoCalibFullValidation"

xcrun swiftc -O \
  "$REPO_ROOT/AnyUpright/Plugin/AnyUprightGeometry.swift" \
  "$REPO_ROOT/AnyUpright/Plugin/AnyUprightLineDetection.swift" \
  "$REPO_ROOT/AnyUpright/Plugin/AnyUprightGeoCalibNeuralOutput.swift" \
  "$REPO_ROOT/AnyUpright/Plugin/AnyUprightGeoCalibCoreML.swift" \
  "$REPO_ROOT/AnyUpright/Plugin/AnyUprightGeoCalibOptimizer.swift" \
  "$REPO_ROOT/AnyUpright/Plugin/AnyUprightGeoCalibPreprocessGeometry.swift" \
  "$REPO_ROOT/AnyUpright/Plugin/AnyUprightGeoCalibHorizonDetector.swift" \
  "$REPO_ROOT/tools/evaluate-swift-geocalib-rotation.swift" \
  -o "$BINARY"

exec "$BINARY" \
  --coreml-model "$REPO_ROOT/AnyUpright/Plugin/GeoCalibCoreML/neural_forward_320x416.mlmodelc" \
  --coreml-model "$REPO_ROOT/AnyUpright/Plugin/GeoCalibCoreML/neural_forward_416x320.mlmodelc" \
  --coreml-model "$REPO_ROOT/AnyUpright/Plugin/GeoCalibCoreML/neural_forward_320x544.mlmodelc" \
  --coreml-model "$REPO_ROOT/AnyUpright/Plugin/GeoCalibCoreML/neural_forward_544x320.mlmodelc" \
  --coreml-model "$REPO_ROOT/AnyUpright/Plugin/GeoCalibCoreML/neural_forward_320x320.mlmodelc" \
  --coreml-model "$REPO_ROOT/AnyUpright/Plugin/GeoCalibCoreML/neural_forward_320x480.mlmodelc" \
  --coreml-model "$REPO_ROOT/AnyUpright/Plugin/GeoCalibCoreML/neural_forward_480x320.mlmodelc" \
  --coreml-model "$REPO_ROOT/AnyUpright/Plugin/GeoCalibCoreML/neural_forward_320x736.mlmodelc" \
  "$@"
