TERMUX_PKG_HOMEPAGE="https://github.com/liuxspro/my-termux-packages"
TERMUX_PKG_DESCRIPTION="最小示例包：hello world，演示自有 Termux 仓库的构建与发布流程"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_VERSION="0.1.0"
TERMUX_PKG_MAINTAINER="liuxspro"
TERMUX_PKG_DEPENDS=""

# 不设置 TERMUX_PKG_SRCURL → 用 termux_step_get_source 钩子提供本地源码
# （官方构建系统同款机制，两边通用）。
# 要从网络获取源码时改为：
#   TERMUX_PKG_SRCURL="https://example.org/hello-$TERMUX_PKG_VERSION.tar.gz"
#   TERMUX_PKG_SHA256="<tarball 的 sha256>"
TERMUX_PKG_SRCURL=""

termux_step_get_source() {
	mkdir -p "$TERMUX_PKG_SRCDIR"
	cp "$TERMUX_PKG_BUILDER_DIR/hello.c" "$TERMUX_PKG_BUILDER_DIR/LICENSE" "$TERMUX_PKG_SRCDIR/"
}

# 源码直接在源码目录里编译（不需要单独的 out-of-tree 构建目录）
TERMUX_PKG_BUILD_IN_SRC=true

# 源码里没有 ./configure 也没有 Makefile，编译规则写在这里
termux_step_make() {
	$CC $CFLAGS hello.c -o hello $LDFLAGS
}

# 安装写法两种都兼容：
#   a) 官方标准：install ... "$TERMUX_PREFIX/bin/hello"（构建系统自动收集产物）
#   b) 直装暂存目录："$TERMUX_PKG_MASSAGEDIR$TERMUX_PREFIX/bin/hello"（本例）
termux_step_make_install() {
	install -Dm755 hello "$TERMUX_PKG_MASSAGEDIR$TERMUX_PREFIX/bin/hello"
}
