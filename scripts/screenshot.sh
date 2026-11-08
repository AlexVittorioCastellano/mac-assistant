#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product AssistenteMac
OUT="$PWD/docs/immagini"
ASSISTENTE_SCREENSHOTS="$OUT" "$(swift build --show-bin-path)/AssistenteMac"
echo "Immagini in $OUT"
