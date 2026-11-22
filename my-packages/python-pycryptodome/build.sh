TERMUX_PKG_HOMEPAGE=https://www.pycryptodome.org/
TERMUX_PKG_DESCRIPTION="A self-contained cryptographic library for Python"
TERMUX_PKG_LICENSE="BSD 2-Clause, Public Domain, Apache-2.0"
TERMUX_PKG_LICENSE_FILE="LICENSE.rst"
TERMUX_PKG_MAINTAINER="@liuxspro"
TERMUX_PKG_VERSION="4.5.0"
TERMUX_PKG_SRCURL="https://github.com/Legrandin/pycryptodome/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256=223878a2066db14756ec41210890546b8a21e6ff392a441637de74265383239a
TERMUX_PKG_AUTO_UPDATE=true
# 只在构建期用 crossenv 里的 pip，运行期不需要 python-pip
TERMUX_PKG_DEPENDS="python"
# setup.py + pyproject.toml 构建 C 扩展，需要 host python + crossenv
TERMUX_PKG_SETUP_PYTHON=true
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_pre_configure() {
	# pycryptodome 故意不把扩展模块链接到 libpython（这样打出的 wheel 更通用），
	# 但 bionic 不像 glibc 那样把解释器符号暴露给 dlopen 出来的 .so，
	# 缺少 DT_NEEDED 时模块会解析不到 CPython C API 符号。
	LDFLAGS+=" -Wl,--no-as-needed -lpython${TERMUX_PYTHON_VERSION}"
}

termux_step_make_install() {
	# --no-build-isolation：使用 crossenv 里的 setuptools，避免 pip 另建隔离环境再下一套
	pip install . --prefix="$TERMUX_PREFIX" -vv --no-build-isolation --no-deps
}
