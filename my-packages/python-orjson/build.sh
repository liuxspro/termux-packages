TERMUX_PKG_HOMEPAGE=https://github.com/ijl/orjson
TERMUX_PKG_DESCRIPTION="Fast, correct Python JSON library supporting dataclasses, datetimes, and numpy"
TERMUX_PKG_LICENSE="MPL-2.0, Apache-2.0, MIT"
TERMUX_PKG_LICENSE_FILE="LICENSE-MPL-2.0, LICENSE-APACHE, LICENSE-MIT"
TERMUX_PKG_MAINTAINER="@liuxspro"
TERMUX_PKG_VERSION="3.13.0"
TERMUX_PKG_SRCURL="https://github.com/ijl/orjson/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256=f2f65003c330507d8ade0fbfffbb30767833a7c9394ab6386eab4aac80bbaba0
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="python"
TERMUX_PKG_BUILD_IN_SRC=true

# termux_setup_rust sources packages/rust/build.sh to get the rustup toolchain
# version. This trimmed repo has no such package, and the fallback would pick up
# this package's own TERMUX_PKG_VERSION, so pin it here instead.
# Keep in sync with TERMUX_PKG_VERSION in termux-packages/packages/rust/build.sh.
TERMUX_RUST_VERSION="1.100.0"

TERMUX_PKG_PYTHON_COMMON_BUILD_DEPS="maturin"

termux_step_pre_configure() {
	termux_setup_rust
	export CARGO_BUILD_TARGET="${CARGO_TARGET_NAME}"
	# pyo3-build-config needs this to avoid probing the host python
	export PYO3_CROSS_LIB_DIR="${TERMUX_PREFIX}/lib"
	export ANDROID_API_LEVEL="${TERMUX_PKG_API_LEVEL}"
}

termux_step_make_install() {
	# --no-build-isolation makes pip use the maturin installed for the build
	# python instead of trying to build one for the target python.
	cross-pip install --no-build-isolation --no-deps . --prefix "$TERMUX_PREFIX"
}

termux_step_post_make_install() {
	# maturin does not link extension modules against libpython, but the Android
	# linker requires the dependency to be recorded.
	local _orjson_so
	_orjson_so=$(find "$TERMUX_PREFIX/lib/python${TERMUX_PYTHON_VERSION}/site-packages/orjson" \
		-maxdepth 1 -name "*.so")
	if [ -z "$_orjson_so" ]; then
		termux_error_exit "Could not find built orjson extension module"
	fi
	patchelf --add-needed "libpython${TERMUX_PYTHON_VERSION}.so" "$_orjson_so"
}
