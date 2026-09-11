#!/bin/bash
# Copy this checkout into the Omarchy plugin directory. Does not enable the
# widget or restart the shell — Keeley does that when Tim asks.

set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="$(python3 - "$src/manifest.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["id"])
PY
)"
parent="$HOME/.config/omarchy/plugins"
dest="$parent/$id"

if [ -L "$dest" ]; then
  echo "Error: $dest is a symlink, not a plugin directory. Remove it and re-run." >&2
  exit 1
fi

stage="$(mktemp -d "$parent/.upcoming.staging.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/bin" "$stage/scripts"
cp "$src/manifest.json" "$src/Model.js" "$src/Service.qml" "$src/BarWidget.qml" "$src/Panel.qml" \
  "$src/README.md" "$src/LICENSE" "$src/THIRD_PARTY_NOTICES.md" "$stage/"
cp "$src/bin/upcoming-ops" "$stage/bin/"
cp "$src/scripts/bounded-job-wrapper.sh" "$stage/scripts/"
chmod 755 "$stage/bin/upcoming-ops" "$stage/scripts/bounded-job-wrapper.sh"

omarchy plugin validate "$stage"

if [ -e "$dest" ]; then
  old="$parent/.upcoming.old.$$"
  mv -f "$dest" "$old"
  if mv -f "$stage" "$dest"; then
    rm -rf "$old"
  else
    rm -rf "$dest" 2>/dev/null || true
    mv -f "$old" "$dest"
    echo "Error: install failed; restored the previous install." >&2
    exit 1
  fi
else
  mv -f "$stage" "$dest"
fi
trap - EXIT

echo "Installed $id to $dest"
echo "Not enabled and the shell was not restarted. When you want it live:"
echo "  omarchy plugin enable $id"
echo "  omarchy restart shell"
