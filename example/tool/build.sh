#!/usr/bin/env bash
# Build/run the example with config/dev.json applied automatically.
#
#   tool/build.sh apk            -> flutter build apk --dart-define-from-file=config/dev.json
#   tool/build.sh ios            -> flutter build ios ...
#   tool/build.sh run            -> flutter run ...
#   tool/build.sh apk --release  -> extra args pass straight through
#
# Override the config per environment: CONFIG=config/prod.json tool/build.sh apk
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-config/dev.json}"
CMD="${1:?usage: tool/build.sh <apk|ios|run|...> [flutter args...]}"
shift

flutter "$([ "$CMD" = run ] && echo run || echo build)" \
  $([ "$CMD" = run ] || echo "$CMD") \
  --dart-define-from-file="$CONFIG" "$@"
