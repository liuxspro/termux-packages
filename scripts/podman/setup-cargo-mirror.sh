#!/bin/bash
#
# Configure the crates.io mirror used by cargo inside the podman builder container

set -euo pipefail

CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
CONFIG="$CARGO_HOME/config.toml"

mkdir -p "$CARGO_HOME"

# Do not silently throw away a hand-written config.
if [ -f "$CONFIG" ] && ! grep -q 'rsproxy\.cn' "$CONFIG"; then
	cp "$CONFIG" "$CONFIG.bak"
	echo "[cargo-mirror] Existing config saved to $CONFIG.bak"
fi

cat > "$CONFIG" <<'EOF'
[source.crates-io]
replace-with = 'rsproxy-sparse'
[source.rsproxy]
registry = "https://rsproxy.cn/crates.io-index"
[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"
[registries.rsproxy]
index = "https://rsproxy.cn/crates.io-index"
[net]
git-fetch-with-cli = true
EOF

echo "[cargo-mirror] Wrote $CONFIG"
