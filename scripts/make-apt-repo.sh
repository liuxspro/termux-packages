#!/usr/bin/env bash
#
# Create an apt repository tree from built .deb files using `termux-apt-repo`
# (https://github.com/termux/termux-apt-repo, the official repo publishing
# tool used by Termux).
#
# Usage:
#   scripts/make-apt-repo.sh [DEB_DIR] [OUT_DIR] [DIST] [COMP]
#
#   DEB_DIR  directory containing .deb files   (default: output)
#   OUT_DIR  apt repository tree to create     (default: apt-repo)
#   DIST     distribution name                 (default: stable)
#   COMP     component name                    (default: main)
#
# Signing:
#   Set SIGN=1 to sign the repository with the default GPG key. This creates
#   both InRelease (for apt on devices) and Release + Release.gpg (detached,
#   required if the repo is consumed by the termux-packages build system as a
#   dependency source, see repo.json and packages/termux-keyring/).
#
# The generated OUT_DIR tree can be published as-is, e.g. via GitHub Pages.
# Users then add to $PREFIX/etc/apt/sources.list.d/<name>.list:
#
#   deb [trusted=yes] $REPO_URL stable main        # unsigned repo
#   deb $REPO_URL stable main                      # signed repo (+ key import)

set -e

DEB_DIR="${1:-output}"
OUT_DIR="${2:-apt-repo}"
DIST="${3:-stable}"
COMP="${4:-main}"
SIGN="${SIGN:-0}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

[ -d "$DEB_DIR" ] || { echo "ERROR: '$DEB_DIR' does not exist" >&2; exit 1; }
ls "$DEB_DIR"/*.deb > /dev/null 2>&1 || { echo "ERROR: no .deb files in '$DEB_DIR'" >&2; exit 1; }

# Install termux-apt-repo if not available (works on any Linux, incl. the
# wslc build container and GitHub Actions runners).
if ! command -v termux-apt-repo > /dev/null 2>&1; then
	echo "Installing termux-apt-repo..."
	# --user installs into ~/.local (never touches the system environment);
	# --break-system-packages is needed on PEP 668 "externally managed"
	# Pythons (Ubuntu 24.04+, GitHub Actions runners).
	python3 -m pip install --user --quiet termux-apt-repo \
		|| python3 -m pip install --user --quiet --break-system-packages termux-apt-repo
	export PATH="$HOME/.local/bin:$PATH"
fi

echo "Creating apt repository at '$OUT_DIR' (dist='$DIST', comp='$COMP')..."
if [ "$SIGN" = "1" ]; then
	termux-apt-repo --sign "$DEB_DIR" "$OUT_DIR" "$DIST" "$COMP"
	# termux-apt-repo only creates the clearsigned InRelease. Also create the
	# detached signature expected by scripts/build/termux_get_repo_files.sh
	# when this repo is used as a dependency source via repo.json.
	gpg --yes --pinentry-mode loopback --digest-algo SHA256 \
		--detach-sign -o "$OUT_DIR/dists/$DIST/Release.gpg" "$OUT_DIR/dists/$DIST/Release"
	echo "Signed: InRelease + Release.gpg (key: $(gpg --list-secret-keys --keyid-format long | grep sec | head -1))"
else
	termux-apt-repo "$DEB_DIR" "$OUT_DIR" "$DIST" "$COMP"
	echo "NOT signed - consumers need '[trusted=yes]' (set SIGN=1 to sign)"
fi

# Sanity check: the Release file must contain the Packages hashes in the
# layout expected by scripts/get_hash_from_file.py.
for arch in $(ls "$OUT_DIR/dists/$DIST/$COMP" | sed -n 's/^binary-//p'); do
	HASH="$(./scripts/get_hash_from_file.py "$OUT_DIR/dists/$DIST/Release" "$arch" "$COMP")"
	[ -n "$HASH" ] || { echo "ERROR: Release is missing hash for $COMP/binary-$arch/Packages" >&2; exit 1; }
done

echo
echo "Done. Publish the '$OUT_DIR' directory at some \$REPO_URL, e.g. GitHub Pages."
echo "Users add to \$PREFIX/etc/apt/sources.list.d/<name>.list:"
if [ "$SIGN" = "1" ]; then
	echo "    deb \$REPO_URL $DIST $COMP"
else
	echo "    deb [trusted=yes] \$REPO_URL $DIST $COMP"
fi
