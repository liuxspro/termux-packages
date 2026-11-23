TERMUX_PKG_HOMEPAGE=https://github.com/pyproj4/pyproj
TERMUX_PKG_DESCRIPTION="Python interface to PROJ (cartographic projections and coordinate transformations library)"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_LICENSE_FILE="LICENSE, LICENSE_proj"
TERMUX_PKG_MAINTAINER="@liuxspro"
TERMUX_PKG_VERSION="3.8.0"
TERMUX_PKG_SRCURL="https://github.com/pyproj4/pyproj/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256=e54d74babf5fed2d9a693670d0b782cd8c76080e509b82256fb5c97f80af5490
TERMUX_PKG_AUTO_UPDATE=true
# 运行期链接 libproj（proj 包）+ libpython；certifi 由自家 python-certifi 包提供
#（import pyproj -> pyproj.network -> import certifi）。
TERMUX_PKG_DEPENDS="libc++, proj, python, python-certifi"
# 只在构建期用 crossenv 里的 pip，运行期不需要
TERMUX_PKG_SETUP_PYTHON=true
# 源码只有 .pyx（不带预生成的 .c），必须用 Cython 现场编译；
# setup.py 里的 freethreading_compatible 编译指令要求 Cython >= 3.1。
# 安装到 build env，crossenv 的 cross python 能通过 PYTHONPATH 直接 import 它。
TERMUX_PKG_PYTHON_COMMON_BUILD_DEPS="'Cython>=3.1'"
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_pre_configure() {
	# setup.py 会执行 $PROJ_DIR/bin/proj 来探测 PROJ 版本；交叉编译时目标架构的
	# proj 无法在构建机上运行，改用环境变量 PROJ_VERSION 显式指定。
	# 版本号直接从 proj 的配方里读，proj 升级时自动跟随。
	local _PROJ_VERSION
	_PROJ_VERSION="$(. "$TERMUX_SCRIPTDIR/packages/proj/build.sh"; echo "$TERMUX_PKG_VERSION")"
	[ -n "$_PROJ_VERSION" ] || termux_error_exit "Failed to determine PROJ version from packages/proj/build.sh"
	export PROJ_VERSION="$_PROJ_VERSION"
	# 让 setup.py 到 $TERMUX_PREFIX/{include,lib} 找 proj.h / libproj
	export PROJ_DIR="$TERMUX_PREFIX"

	# Cython 扩展模块默认不链接 libpython（这样打出的 wheel 更通用），
	# 但 bionic 不像 glibc 那样把解释器符号暴露给 dlopen 出来的 .so，
	# 缺少 DT_NEEDED 时模块会解析不到 CPython C API 符号。
	LDFLAGS+=" -Wl,--no-as-needed -lpython${TERMUX_PYTHON_VERSION}"
}

termux_step_make() {
	# 构建全部由下面的 pip install 完成。
	# 必须跳过默认的 make：源码里带的 Makefile 只是开发用目标（lint/docs），
	# 默认 make 步骤会匹配到它并跑里面的 python 脚本。
	:
}

termux_step_make_install() {
	# --no-build-isolation：使用 crossenv 里的 setuptools/Cython，
	# 避免 pip 另建隔离环境再联网下一套构建依赖
	pip install . --prefix="$TERMUX_PREFIX" -vv --no-build-isolation --no-deps
}

termux_step_post_make_install() {
	# certifi 改由 python-certifi（apt）提供。抹掉 dist-info METADATA 里的
	# Requires-Dist，否则 termux_step_create_python_debscripts 会检测到它并往
	# postinst 塞一条 pip3 install pyproj：那会强制要求依赖 python-pip，
	# 且装包时联网 PyPI。依赖关系改写进 TERMUX_PKG_DEPENDS（Debian 打包惯例）。
	local _metadata
	_metadata="$(find "$TERMUX_PREFIX/lib/python${TERMUX_PYTHON_VERSION}/site-packages" \
		-maxdepth 2 -path '*pyproj*.dist-info/METADATA')"
	[ -n "$_metadata" ] || termux_error_exit "Could not find pyproj dist-info METADATA"
	sed -i '/^Requires-Dist: /d' "$_metadata"
}
