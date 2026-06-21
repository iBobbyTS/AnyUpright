#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="${TMPDIR:-/tmp}/AnyUprightSwiftGeoCalibFullValidation"

xcrun swiftc -O \
  "$REPO_ROOT/AnyUpright/Plugin/AnyUprightGeometry.swift" \
  "$REPO_ROOT/AnyUpright/Plugin/AnyUprightLineDetection.swift" \
  "$REPO_ROOT/AnyUpright/Plugin/AnyUprightGeoCalibNeuralPrototype.swift" \
  "$REPO_ROOT/AnyUpright/Plugin/AnyUprightGeoCalibRuntimeBundle.swift" \
  "$REPO_ROOT/AnyUpright/Plugin/AnyUprightGeoCalibOptimizer.swift" \
  "$REPO_ROOT/AnyUpright/Plugin/AnyUprightGeoCalibHorizonDetector.swift" \
  "$REPO_ROOT/tools/evaluate-swift-geocalib-rotation.swift" \
  -o "$BINARY"

exec "$BINARY" \
  --runtime-bundle "$REPO_ROOT/AnyUpright/Plugin/GeoCalibRuntime" \
  --metal-source "$REPO_ROOT/AnyUpright/Plugin/AnyUprightGeoCalib.metal" \
  "$@"
