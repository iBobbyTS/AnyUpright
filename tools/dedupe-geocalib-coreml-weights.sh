#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COREML_ROOT="${1:-$REPO_ROOT/AnyUpright/Plugin/GeoCalibCoreML}"
CANONICAL_MODEL="neural_forward_320x416.mlmodelc"
CANONICAL_WEIGHT="$COREML_ROOT/$CANONICAL_MODEL/weights/weight.bin"
SHARED_TARGET="../../$CANONICAL_MODEL/weights/weight.bin"

if [[ ! -f "$CANONICAL_WEIGHT" ]]; then
  print -u2 "missing canonical Core ML weight: $CANONICAL_WEIGHT"
  exit 1
fi

canonical_hash="$(shasum -a 256 "$CANONICAL_WEIGHT" | awk '{print $1}')"
deduped_count=0
already_count=0

for model_dir in "$COREML_ROOT"/neural_forward_*.mlmodelc; do
  [[ -d "$model_dir" ]] || continue
  model_name="$(basename "$model_dir")"
  [[ "$model_name" != "$CANONICAL_MODEL" ]] || continue

  weight="$model_dir/weights/weight.bin"
  if [[ -L "$weight" ]]; then
    current_target="$(readlink "$weight")"
    if [[ "$current_target" == "$SHARED_TARGET" ]]; then
      print "$model_name weight is already deduped"
      already_count=$((already_count + 1))
      continue
    fi
    print -u2 "$model_name weight is a symlink to an unexpected target: $current_target"
    exit 1
  fi

  if [[ ! -f "$weight" ]]; then
    print -u2 "missing Core ML weight: $weight"
    exit 1
  fi

  weight_hash="$(shasum -a 256 "$weight" | awk '{print $1}')"
  if [[ "$canonical_hash" != "$weight_hash" ]]; then
    print -u2 "refusing to dedupe: $CANONICAL_MODEL and $model_name weights differ"
    print -u2 "$CANONICAL_MODEL: $canonical_hash"
    print -u2 "$model_name: $weight_hash"
    exit 1
  fi

  rm "$weight"
  ln -s "$SHARED_TARGET" "$weight"
  print "deduped $model_name weight via relative symlink"
  deduped_count=$((deduped_count + 1))

  if [[ ! -f "$weight" ]]; then
    print -u2 "dedupe validation failed for $model_name: symlink does not resolve to a readable file"
    exit 1
  fi
done

if [[ $deduped_count -eq 0 && $already_count -eq 0 ]]; then
  print "no additional Core ML models found to dedupe"
else
  print "Core ML weight dedupe complete: deduped=$deduped_count already=$already_count"
fi

print ""
du -sh "$COREML_ROOT" "$COREML_ROOT"/*.mlmodelc "$COREML_ROOT"/*.mlmodelc/weights
