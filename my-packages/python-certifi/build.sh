TERMUX_PKG_HOMEPAGE=https://github.com/certifi/python-certifi
TERMUX_PKG_DESCRIPTION="Python package for providing Mozilla's CA Bundle"
TERMUX_PKG_LICENSE="MPL-2.0"
TERMUX_PKG_LICENSE_FILE="LICENSE"
TERMUX_PKG_MAINTAINER="@liuxspro"
TERMUX_PKG_VERSION="2026.11.20"
TERMUX_PKG_SRCURL="https://github.com/certifi/python-certifi/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256=dad3e34e9f6a26b7f30881556bd6d3f79ccf15fd0d88c8f9e565be4f0fb28835
TERMUX_PKG_AUTO_UPDATE=true
# 纯 Python 包（cacert.pem 由 setup.py 的 package_data 打进去），运行期只需要 python。
# 自己的 METADATA 没有 Requires-Dist，不会触发 postinst 里的 pip3，无需 python-pip。
TERMUX_PKG_DEPENDS="python"
# wheel 由 build-pip 装进构建环境（会自动启用 crossenv）
TERMUX_PKG_PYTHON_COMMON_BUILD_DEPS="wheel"
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_make() {
	# 必须跳过默认 make：它会匹配到源码里的 Makefile，而默认目标是
	# "update"（curl mkcert.org 重新生成并覆盖 cacert.pem），绝不能在构建时跑。
	:
}

termux_step_make_install() {
	# --no-build-isolation：使用 crossenv 里的 setuptools，避免 pip 另建隔离环境
	pip install . --prefix="$TERMUX_PREFIX" -vv --no-build-isolation --no-deps
}
