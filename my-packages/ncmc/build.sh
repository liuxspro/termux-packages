TERMUX_PKG_HOMEPAGE=https://github.com/magic-akari/ncmc
TERMUX_PKG_DESCRIPTION="Convert encrypted NetEase Cloud Music (.ncm) files to original music files"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_LICENSE_FILE="LICENSE"
TERMUX_PKG_MAINTAINER="@liuxspro"
TERMUX_PKG_VERSION="0.2.11"
TERMUX_PKG_SRCURL="https://github.com/magic-akari/ncmc/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256=c3d0f04e6e90f5ca470ef97afa325ae96d1b2fe90d41342a58810754ed19aeeb
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_BUILD_IN_SRC=true

# termux_setup_rust sources packages/rust/build.sh to get the rustup toolchain
# version. This trimmed repo has no such package, and the fallback would pick up
# this package's own TERMUX_PKG_VERSION, so pin it here instead.
# Keep in sync with TERMUX_PKG_VERSION in termux-packages/packages/rust/build.sh.
TERMUX_RUST_VERSION="1.100.0"

termux_step_pre_configure() {
	# The upstream rust-toolchain.toml pins 1.81.0, which overrides the toolchain
	# selected by termux_setup_rust; that pinned toolchain has no android target.
	rm -f rust-toolchain.toml
	termux_setup_rust
}

termux_step_make() {
	# The workspace also contains ncmc_wasm, which is only used for wasm builds.
	cargo build --jobs "$TERMUX_PKG_MAKE_PROCESSES" --target "$CARGO_TARGET_NAME" --release --locked -p ncmc
}

termux_step_make_install() {
	install -Dm755 "target/${CARGO_TARGET_NAME}/release/ncmc" "$TERMUX_PREFIX/bin/ncmc"
}
