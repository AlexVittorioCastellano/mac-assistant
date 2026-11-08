#!/bin/zsh
# Rigenera le immagini del README (docs/immagini) con DATI FINTI e le
# risposte vere del modello sul Mac. Disegna fuori dallo schermo: non cattura
# lo schermo e non usa dati del tuo Mac. Servono Apple Intelligence attiva.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product AssistenteMac
OUT="$PWD/docs/immagini"
ASSISTENTE_SCREENSHOTS="$OUT" "$(swift build --show-bin-path)/AssistenteMac"
echo "Immagini in $OUT"
