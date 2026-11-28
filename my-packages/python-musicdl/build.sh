TERMUX_PKG_HOMEPAGE=https://github.com/CharlesPikachu/musicdl
TERMUX_PKG_DESCRIPTION="Musicdl: A lightweight music downloader written in pure python."
TERMUX_PKG_LICENSE="non-free"
TERMUX_PKG_LICENSE_FILE="LICENSE"
TERMUX_PKG_MAINTAINER="@liuxspro"
TERMUX_PKG_VERSION="2.14.2"
TERMUX_PKG_SRCURL="https://files.pythonhosted.org/packages/f8/df/8202a85afc2430d9b11dc113cff38e34bfe4471c91f43b97b73c74d49470/musicdl-2.14.2.tar.gz"
TERMUX_PKG_SHA256=74d4b78c26bc2445d5d4d06902c4fed6b49645e8fb721935d2569f24294ff1e1
TERMUX_PKG_AUTO_UPDATE=false

# 运行期依赖分两类：
# 1) C / Rust 扩展，以及版本约束与 Termux 打包版本冲突的库，用 Termux 包：
#    orjson 与 pycryptodome 来自自建源，pycryptodomex / lxml / cryptography 来自 termux-main。
#    lxml 必须显式依赖：全包 40+ 处 BeautifulSoup(html, "lxml")，缺了会让绝大多数
#    网页音源在解析时抛 FeatureNotFound。
# 2) 纯 python 依赖由 postinst 里的 pip3 安装，见 TERMUX_PKG_PYTHON_RUNTIME_DEPS。
# python-pip 是 postinst 能执行 pip3 的前提，缺了打包阶段会 termux_error_exit。
TERMUX_PKG_DEPENDS="python, python-pip, python-cryptography, python-lxml, python-pycryptodome, python-pycryptodomex, python-orjson"
# 部分音源需要的外部 CLI：ffmpeg（apple/tidal/moov/soundcloud 等）、nodejs（youtube）
TERMUX_PKG_RECOMMENDS="ffmpeg, nodejs"

# 构建期：没有 pyproject.toml，走 setup.py，只需要 setuptools + wheel
TERMUX_PKG_PYTHON_COMMON_BUILD_DEPS="setuptools, wheel"

# 纯 python 依赖；版本约束沿用 METADATA 里的 Requires-Dist，这里不重复钉版本
TERMUX_PKG_PYTHON_RUNTIME_DEPS="aigpy==2022.7.8.1, beautifulsoup4, bleach, click, emoji, fake-useragent, filetype, json-repair, m3u8, mutagen, pathvalidate, platformdirs, prettytable, prompt-toolkit, puremagic, pywidevine, requests, rich, tabulate, tinytag, typing-extensions, wcwidth, ytmusicapi"

TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true

termux_step_post_make_install() {
	# termux_step_create_python_debscripts.sh:35-39 会把包自己的 pip 名追加进 postinst 的
	# `pip3 install ...`，于是 pip 会顺着 musicdl 的 Requires-Dist 解析整棵依赖树。
	# 这里删掉 Termux 上装不了（av/curl-cffi/nodejs-wheel/brotli，没有 Android 轮子，
	# 现场编译必失败）以及版本与 apt 包冲突（pycryptodome<4 vs 4.5.0、
	# cryptography<47 vs 50.x，pip 会去 PyPI 重新编译）的条目。
	# av(Pythonic bindings for FFmpeg's libraries. )缺失会回退使用 ffmpeg 命令行
	local _metadata="$TERMUX_PYTHON_HOME/site-packages/musicdl-$TERMUX_PKG_VERSION.dist-info/METADATA"
	sed -i -E '/^Requires-Dist: (av|brotli|curl-cffi|nodejs-wheel|pycryptodome|cryptography)([^A-Za-z0-9_-]|$)/d' "$_metadata"
	if grep -qE '^Requires-Dist: (av|brotli|curl-cffi|nodejs-wheel|pycryptodome|cryptography)([^A-Za-z0-9_-]|$)' "$_metadata"; then
		termux_error_exit "failed to prune unsupported Requires-Dist from $_metadata"
	fi
}
