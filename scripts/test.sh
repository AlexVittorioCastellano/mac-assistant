#!/bin/zsh
# Esegue i test. Con i soli Command Line Tools (senza Xcode) il plugin delle
# macro di Swift Testing non viene trovato da solo: qui gli indichiamo dove sta.
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools && -d $PLUGINS ]]; then
    swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
else
    swift test "$@"
fi
