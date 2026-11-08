#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export ASSISTENTE_LINGUA=${ASSISTENTE_LINGUA:-it}
PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools && -d $PLUGINS ]]; then
    swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
else
    swift test "$@"
fi
